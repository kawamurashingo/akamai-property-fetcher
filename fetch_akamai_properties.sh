#!/bin/bash

# Akamai APIのベースURL（適宜変更してください）
BASE_URL="https://akab-xxx.luna.akamaiapis.net"

# 出力ディレクトリを設定
OUTPUT_DIR="property"

# 出力ディレクトリを作成
mkdir -p "$OUTPUT_DIR"

# 1. グループ情報を取得
GROUPS_JSON=$(./akamai_edgegrid.sh -X GET "$BASE_URL/papi/v1/groups" 2>/dev/null)

# エラーチェック
if [ $? -ne 0 ] || [ -z "$GROUPS_JSON" ]; then
    echo "グループ情報の取得に失敗しました。"
    exit 1
fi

# 2. contractIdとgroupIdのペアを抽出
CONTRACT_IDS=($(echo "$GROUPS_JSON" | jq -r '.groups.items[] | .contractIds[]'))
GROUP_IDS=($(echo "$GROUPS_JSON" | jq -r '.groups.items[].groupId'))

# 3. 各contractIdとgroupIdの組み合わせでプロパティを取得
for ((i=0; i<${#CONTRACT_IDS[@]}; i++)); do
    CONTRACT_ID="${CONTRACT_IDS[$i]}"
    GROUP_ID="${GROUP_IDS[$i]}"

    echo "Processing Contract ID: $CONTRACT_ID, Group ID: $GROUP_ID"

    # プロパティ一覧を取得
    PROPERTIES_JSON=$(./akamai_edgegrid.sh -X GET "$BASE_URL/papi/v1/properties?contractId=$CONTRACT_ID&groupId=$GROUP_ID" 2>/dev/null)

    # エラーチェック
    if [ $? -ne 0 ] || [ -z "$PROPERTIES_JSON" ]; then
        echo "Contract ID: $CONTRACT_ID, Group ID: $GROUP_ID のプロパティ取得に失敗しました。"
        continue
    fi

    # プロパティIDとプロパティ名を抽出
    PROPERTY_IDS=($(echo "$PROPERTIES_JSON" | jq -r '.properties.items[].propertyId'))
    PROPERTY_NAMES=($(echo "$PROPERTIES_JSON" | jq -r '.properties.items[].propertyName'))

    # 各プロパティのルール情報を取得して保存
    for ((j=0; j<${#PROPERTY_IDS[@]}; j++)); do
        PROPERTY_ID="${PROPERTY_IDS[$j]}"
        PROPERTY_NAME="${PROPERTY_NAMES[$j]}"

        echo "  Processing Property: $PROPERTY_NAME (ID: $PROPERTY_ID)"

        # 不適切な文字を削除してディレクトリ名を作成
        SAFE_PROPERTY_NAME=$(echo "$PROPERTY_NAME" | tr -d '[:cntrl:]/:*?"<>|')
        DIR_NAME="$OUTPUT_DIR/${SAFE_PROPERTY_NAME// /_}"

        # ディレクトリを作成
        mkdir -p "$DIR_NAME"

        # activations エンドポイントからアクティブなバージョンを取得
        ACTIVATIONS_JSON=$(./akamai_edgegrid.sh -X GET "$BASE_URL/papi/v1/properties/$PROPERTY_ID/activations?contractId=$CONTRACT_ID&groupId=$GROUP_ID" 2>/dev/null)

        # エラーチェック
        if [ $? -ne 0 ] || [ -z "$ACTIVATIONS_JSON" ]; then
            echo "    プロパティ $PROPERTY_NAME のアクティベーション情報取得に失敗しました。"
            continue
        fi

        # ステージングの最新アクティブなバージョンを取得
        STAGING_VERSION=$(echo "$ACTIVATIONS_JSON" | jq -r '
            [ .activations.items[] | select(.network=="STAGING" and .status=="ACTIVE") ] 
            | sort_by(.updateDate) 
            | last 
            | .propertyVersion // empty')

        # プロダクションの最新アクティブなバージョンを取得
        PRODUCTION_VERSION=$(echo "$ACTIVATIONS_JSON" | jq -r '
            [ .activations.items[] | select(.network=="PRODUCTION" and .status=="ACTIVE") ] 
            | sort_by(.updateDate) 
            | last 
            | .propertyVersion // empty')

        # ステージングのルール情報を取得して保存
        if [ -n "$STAGING_VERSION" ]; then
            echo "    Fetching staging version: $STAGING_VERSION"
            STAGING_RULES_JSON=$(./akamai_edgegrid.sh -X GET "$BASE_URL/papi/v1/properties/$PROPERTY_ID/versions/$STAGING_VERSION/rules?contractId=$CONTRACT_ID&groupId=$GROUP_ID" 2>/dev/null)

            if [ $? -eq 0 ] && [ -n "$STAGING_RULES_JSON" ]; then
                echo "$STAGING_RULES_JSON" > "$DIR_NAME/staging.json"
                echo "    Saved staging rules to $DIR_NAME/staging.json"
            else
                echo "    ステージングのルール情報取得に失敗しました。"
            fi
        else
            echo "    ステージング環境にアクティベートされていません。"
        fi

        # プロダクションのルール情報を取得して保存
        if [ -n "$PRODUCTION_VERSION" ]; then
            echo "    Fetching production version: $PRODUCTION_VERSION"
            PRODUCTION_RULES_JSON=$(./akamai_edgegrid.sh -X GET "$BASE_URL/papi/v1/properties/$PROPERTY_ID/versions/$PRODUCTION_VERSION/rules?contractId=$CONTRACT_ID&groupId=$GROUP_ID" 2>/dev/null)

            if [ $? -eq 0 ] && [ -n "$PRODUCTION_RULES_JSON" ]; then
                echo "$PRODUCTION_RULES_JSON" > "$DIR_NAME/production.json"
                echo "    Saved production rules to $DIR_NAME/production.json"
            else
                echo "    プロダクションのルール情報取得に失敗しました。"
            fi
        else
            echo "    プロダクション環境にアクティベートされていません。"
        fi
    done
done
