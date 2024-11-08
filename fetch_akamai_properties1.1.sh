#!/bin/bash

# .edgerc ファイルから変数を読み込む関数
BASE_URL="https://`grep host $HOME/.edgerc | awk '{print $3}'`"

# 出力ディレクトリを設定
OUTPUT_DIR="property"

# 出力ディレクトリを作成
mkdir -p "$OUTPUT_DIR"

# 最大並列ジョブ数
MAX_JOBS=4

# 並列実行を管理する関数
wait_for_jobs() {
    while [ $(jobs -p | wc -l) -ge "$MAX_JOBS" ]; do
        sleep 1
    done
}

# プロパティのルール情報を取得する関数
fetch_property() {
    local CONTRACT_ID="$1"
    local GROUP_ID="$2"
    local PROPERTY_ID="$3"
    local PROPERTY_NAME="$4"

    echo "  Processing Property: $PROPERTY_NAME (ID: $PROPERTY_ID)"

    SAFE_PROPERTY_NAME=$(echo "$PROPERTY_NAME" | tr -d '[:cntrl:]/:*?"<>|')
    DIR_NAME="$OUTPUT_DIR/${SAFE_PROPERTY_NAME// /_}"
    mkdir -p "$DIR_NAME"

    ACTIVATIONS_JSON=$(./akamai_edgegrid.sh -X GET "$BASE_URL/papi/v1/properties/$PROPERTY_ID/activations?contractId=$CONTRACT_ID&groupId=$GROUP_ID" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$ACTIVATIONS_JSON" ] || [ "$ACTIVATIONS_JSON" == "null" ]; then
        echo "    プロパティ $PROPERTY_NAME のアクティベーション情報取得に失敗しました。"
        return
    fi

    # jqの配列アクセスに '?' を追加してエラーを回避
    STAGING_VERSION=$(echo "$ACTIVATIONS_JSON" | jq -r '
        [ (.activations.items[]? | select(.network=="STAGING" and .status=="ACTIVE")) ] 
        | sort_by(.updateDate) 
        | last 
        | .propertyVersion // empty')

    PRODUCTION_VERSION=$(echo "$ACTIVATIONS_JSON" | jq -r '
        [ (.activations.items[]? | select(.network=="PRODUCTION" and .status=="ACTIVE")) ] 
        | sort_by(.updateDate) 
        | last 
        | .propertyVersion // empty')

    if [ -n "$STAGING_VERSION" ]; then
        STAGING_RULES_JSON=$(./akamai_edgegrid.sh -X GET "$BASE_URL/papi/v1/properties/$PROPERTY_ID/versions/$STAGING_VERSION/rules?contractId=$CONTRACT_ID&groupId=$GROUP_ID" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$STAGING_RULES_JSON" ] && [ "$STAGING_RULES_JSON" != "null" ]; then
            echo "$STAGING_RULES_JSON" > "$DIR_NAME/staging.json"
            echo "    Saved staging rules to $DIR_NAME/staging.json"
        else
            echo "    ステージングのルール情報取得に失敗しました。"
        fi
    else
        echo "    ステージング環境にアクティベートされていません。"
    fi

    if [ -n "$PRODUCTION_VERSION" ]; then
        PRODUCTION_RULES_JSON=$(./akamai_edgegrid.sh -X GET "$BASE_URL/papi/v1/properties/$PROPERTY_ID/versions/$PRODUCTION_VERSION/rules?contractId=$CONTRACT_ID&groupId=$GROUP_ID" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$PRODUCTION_RULES_JSON" ] && [ "$PRODUCTION_RULES_JSON" != "null" ]; then
            echo "$PRODUCTION_RULES_JSON" > "$DIR_NAME/production.json"
            echo "    Saved production rules to $DIR_NAME/production.json"
        else
            echo "    プロダクションのルール情報取得に失敗しました。"
        fi
    else
        echo "    プロダクション環境にアクティベートされていません。"
    fi
}

# グループ情報を取得
GROUPS_JSON=$(./akamai_edgegrid.sh -X GET "$BASE_URL/papi/v1/groups" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$GROUPS_JSON" ] || [ "$GROUPS_JSON" == "null" ]; then
    echo "グループ情報の取得に失敗しました。"
    exit 1
fi

# contractIdとgroupIdのペアを抽出
CONTRACT_IDS=($(echo "$GROUPS_JSON" | jq -r '.groups.items[]? | .contractIds[]?'))
GROUP_IDS=($(echo "$GROUPS_JSON" | jq -r '.groups.items[]? | .groupId'))

# 各 contractId と groupId の組み合わせで並列処理を実行
for ((i=0; i<${#CONTRACT_IDS[@]}; i++)); do
    CONTRACT_ID="${CONTRACT_IDS[$i]}"
    GROUP_ID="${GROUP_IDS[$i]}"

    PROPERTIES_JSON=$(./akamai_edgegrid.sh -X GET "$BASE_URL/papi/v1/properties?contractId=$CONTRACT_ID&groupId=$GROUP_ID" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$PROPERTIES_JSON" ] || [ "$PROPERTIES_JSON" == "null" ]; then
        echo "Contract ID: $CONTRACT_ID, Group ID: $GROUP_ID のプロパティ取得に失敗しました。"
        continue
    fi

    PROPERTY_IDS=($(echo "$PROPERTIES_JSON" | jq -r '.properties.items[]? | .propertyId'))
    PROPERTY_NAMES=($(echo "$PROPERTIES_JSON" | jq -r '.properties.items[]? | .propertyName'))

    for ((j=0; j<${#PROPERTY_IDS[@]}; j++)); do
        PROPERTY_ID="${PROPERTY_IDS[$j]}"
        PROPERTY_NAME="${PROPERTY_NAMES[$j]}"

        # 並列ジョブが制限を超えたら待機
        wait_for_jobs

        # 並列でプロパティを取得
        fetch_property "$CONTRACT_ID" "$GROUP_ID" "$PROPERTY_ID" "$PROPERTY_NAME" &
    done
done

# すべてのジョブが完了するのを待つ
wait
