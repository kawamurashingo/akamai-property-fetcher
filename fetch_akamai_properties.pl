use strict;
use warnings;
use Akamai::Edgegrid;
use JSON;
use File::Spec;
use File::Path 'make_path';

# .edgercファイルから認証情報を読み込み、Akamai::Edgegridエージェントを初期化
my $agent = Akamai::Edgegrid->new(
    config_file => "$ENV{HOME}/.edgerc",
    section     => "default"
);

# APIのベースURLを設定
my $baseurl = "https://" . $agent->{host};

# 契約IDの取得エンドポイント
my $contracts_endpoint = "$baseurl/papi/v1/contracts";
my $contracts_resp = $agent->get($contracts_endpoint);
die "契約IDの取得エラー: " . $contracts_resp->status_line unless $contracts_resp->is_success;
my $contracts_data = decode_json($contracts_resp->decoded_content);
my @contract_ids = map { $_->{contractId} } @{ $contracts_data->{contracts}->{items} };

# グループIDの取得エンドポイント
my $groups_endpoint = "$baseurl/papi/v1/groups";
my $groups_resp = $agent->get($groups_endpoint);
die "グループIDの取得エラー: " . $groups_resp->status_line unless $groups_resp->is_success;
my $groups_data = decode_json($groups_resp->decoded_content);
my @group_ids = map { $_->{groupId} } @{ $groups_data->{groups}->{items} };

# 全ての契約IDとグループIDの組み合わせを処理
foreach my $contract_id (@contract_ids) {
    foreach my $group_id (@group_ids) {
        my $properties_endpoint = "$baseurl/papi/v1/properties?contractId=$contract_id&groupId=$group_id";
        my $properties_resp = $agent->get($properties_endpoint);

        if ($properties_resp->is_success) {
            # プロパティ情報の取得
            my $properties_data = decode_json($properties_resp->decoded_content);
            my $properties = $properties_data->{properties}->{items};

            foreach my $property (@$properties) {
                my $property_id = $property->{propertyId};
                my $property_name = $property->{propertyName};

                # プロパティ用ディレクトリを作成
                my $base_dir = "property";
                my $property_dir = File::Spec->catdir($base_dir, $property_name);
                make_path($property_dir) unless -d $property_dir;

                # アクティベートされたバージョンを取得
                my $activations_endpoint = "$baseurl/papi/v1/properties/$property_id/activations?contractId=$contract_id&groupId=$group_id";
                my $activations_resp = $agent->get($activations_endpoint);

                if ($activations_resp->is_success) {
                    my $activations_data = decode_json($activations_resp->decoded_content);

                    # ステージングとプロダクションのアクティベートされたバージョンを検索
                    my ($staging_version, $production_version);
                    foreach my $activation (@{ $activations_data->{activations}->{items} }) {
                        if ($activation->{network} eq 'STAGING' && $activation->{status} eq 'ACTIVE') {
                            $staging_version = $activation->{propertyVersion};
                        }
                        if ($activation->{network} eq 'PRODUCTION' && $activation->{status} eq 'ACTIVE') {
                            $production_version = $activation->{propertyVersion};
                        }
                    }

                    # ステージングバージョンの詳細設定取得と保存
                    if (defined $staging_version) {
                        my $staging_rules_endpoint = "$baseurl/papi/v1/properties/$property_id/versions/$staging_version/rules?contractId=$contract_id&groupId=$group_id";
                        my $staging_rules_resp = $agent->get($staging_rules_endpoint);

                        if ($staging_rules_resp->is_success) {
                            my $staging_rules_content = $staging_rules_resp->decoded_content;
                            my $staging_file_path = File::Spec->catfile($property_dir, "staging.json");

                            open my $fh, '>', $staging_file_path or die "ファイルの作成に失敗しました: $staging_file_path";
                            print $fh $staging_rules_content;
                            close $fh;

                            print "ステージング環境のアクティベートされたプロパティ詳細設定を保存しました: $staging_file_path\n";
                        } else {
                            warn "ステージングバージョン詳細設定の取得エラー ($property_name): " . $staging_rules_resp->status_line . " - スキップします\n";
                        }
                    }

                    # プロダクションバージョンの詳細設定取得と保存
                    if (defined $production_version) {
                        my $production_rules_endpoint = "$baseurl/papi/v1/properties/$property_id/versions/$production_version/rules?contractId=$contract_id&groupId=$group_id";
                        my $production_rules_resp = $agent->get($production_rules_endpoint);

                        if ($production_rules_resp->is_success) {
                            my $production_rules_content = $production_rules_resp->decoded_content;
                            my $production_file_path = File::Spec->catfile($property_dir, "production.json");

                            open my $fh, '>', $production_file_path or die "ファイルの作成に失敗しました: $production_file_path";
                            print $fh $production_rules_content;
                            close $fh;

                            print "プロダクション環境のアクティベートされたプロパティ詳細設定を保存しました: $production_file_path\n";
                        } else {
                            warn "プロダクションバージョン詳細設定の取得エラー ($property_name): " . $production_rules_resp->status_line . " - スキップします\n";
                        }
                    }
                } else {
                    warn "アクティベーション情報の取得エラー ($property_name): " . $activations_resp->status_line . " - スキップします\n";
                }
            }
        } elsif ($properties_resp->code == 403 || $properties_resp->code == 404) {
            warn "プロパティ一覧の取得エラー (契約ID: $contract_id, グループID: $group_id): " . $properties_resp->status_line . " - スキップします\n";
        } else {
            die "予期しないエラー (契約ID: $contract_id, グループID: $group_id): " . $properties_resp->status_line;
        }
    }
}
