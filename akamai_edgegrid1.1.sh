#!/bin/bash

# .edgerc ファイルから変数を読み込む関数
CLIENT_TOKEN="`grep client_token $HOME/.edgerc | awk '{print $3}'`"
CLIENT_SECRET="`grep client_secret $HOME/.edgerc | awk '{print $3}'`"
ACCESS_TOKEN="`grep access_token $HOME/.edgerc | awk '{print $3}'`"
MAX_BODY=131072

# HMAC-SHA256をBase64でエンコードする関数
hmac_sha256_base64() {
    local data="$1"
    local key="$2"
    echo -n "$data" | openssl dgst -binary -sha256 -hmac "$key" | openssl base64 | tr -d '\n'
}

# SHA256をBase64でエンコードする関数
sha256_base64() {
    local data="$1"
    echo -n "$data" | openssl dgst -binary -sha256 | openssl base64 | tr -d '\n'
}

# タイムスタンプを生成する関数
generate_timestamp() {
    date -u +"%Y%m%dT%H:%M:%S+0000"
}

# ノンス（UUID）を生成する関数
generate_nonce() {
    uuidgen | tr -d '-'
}

# サインキーを生成する関数
create_signing_key() {
    local timestamp="$1"
    local client_secret="$2"
    hmac_sha256_base64 "$timestamp" "$client_secret"
}

# コンテンツハッシュを生成する関数
make_content_hash() {
    local method="$1"
    local body="$2"
    local max_body="$3"
    if [ "$method" == "POST" ] && [ -n "$body" ]; then
        local body_length=${#body}
        if [ "$body_length" -gt "$max_body" ]; then
            body="${body:0:$max_body}"
        fi
        sha256_base64 "$body"
    else
        echo ""
    fi
}

# 署名用のデータを作成する関数
make_data_to_sign() {
    local method="$1"
    local scheme="$2"
    local host="$3"
    local path_query="$4"
    local headers="$5"
    local content_hash="$6"
    local auth_header="$7"
    echo -ne "$method\t$scheme\t$host\t$path_query\t$headers\t$content_hash\t$auth_header"
}

# リクエストに署名する関数
sign_request() {
    local data_to_sign="$1"
    local signing_key="$2"
    hmac_sha256_base64 "$data_to_sign" "$signing_key"
}

# 認証ヘッダーを作成する関数
make_auth_header() {
    local client_token="$1"
    local access_token="$2"
    local timestamp="$3"
    local nonce="$4"
    local signature="$5"
    echo "EG1-HMAC-SHA256 client_token=$client_token;access_token=$access_token;timestamp=$timestamp;nonce=$nonce;signature=$signature"
}

# URLを解析する関数
parse_url() {
    local url="$1"
    scheme="$(echo "$url" | awk -F:// '{print $1}')"
    rest="$(echo "$url" | awk -F:// '{print $2}')"
    host="$(echo "$rest" | cut -d/ -f1)"
    path_query="/$(echo "$rest" | cut -d/ -f2-)"
}

# メイン処理
main() {
    # リクエストのメソッド、ヘッダー、データ、URLを取得
    METHOD="GET"
    DATA=""
    HEADERS=()
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            -X)
                METHOD="$2"
                shift
                shift
                ;;
            -H)
                HEADERS+=("$2")
                shift
                shift
                ;;
            --data)
                DATA="$2"
                shift
                shift
                ;;
            *)
                URL="$1"
                shift
                ;;
        esac
    done

    if [ -z "$URL" ]; then
        echo "Usage: $0 -X METHOD -H 'Header: Value' --data 'DATA' URL"
        exit 1
    fi

    timestamp=$(generate_timestamp)
    nonce=$(generate_nonce)
    auth_header="EG1-HMAC-SHA256 client_token=$CLIENT_TOKEN;access_token=$ACCESS_TOKEN;timestamp=$timestamp;nonce=$nonce;"

    signing_key=$(create_signing_key "$timestamp" "$CLIENT_SECRET")

    parse_url "$URL"

    # ヘッダーの正規化はここでは省略しています
    canonicalized_headers=""

    content_hash=$(make_content_hash "$METHOD" "$DATA" "$MAX_BODY")

    data_to_sign=$(make_data_to_sign "$METHOD" "$scheme" "$host" "$path_query" "$canonicalized_headers" "$content_hash" "$auth_header")

    signature=$(sign_request "$data_to_sign" "$signing_key")

    auth_header=$(make_auth_header "$CLIENT_TOKEN" "$ACCESS_TOKEN" "$timestamp" "$nonce" "$signature")

    # リクエストを送信
    if [ "$METHOD" == "GET" ]; then
        curl -X "$METHOD" -H "Authorization: $auth_header" "$URL"
    elif [ "$METHOD" == "POST" ]; then
        curl -X "$METHOD" -H "Authorization: $auth_header" --data "$DATA" "$URL"
    else
        echo "Unsupported method: $METHOD"
        exit 1
    fi
}

main "$@"
