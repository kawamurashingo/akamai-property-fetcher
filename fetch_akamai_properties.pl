use strict;
use warnings;
use Akamai::Edgegrid;
use JSON;
use File::Spec;
use File::Path 'make_path';

# Initialize the Akamai::Edgegrid agent by reading credentials from the .edgerc file
my $agent = Akamai::Edgegrid->new(
    config_file => "$ENV{HOME}/.edgerc",
    section     => "default"
);

# Set the base URL for the API
my $baseurl = "https://" . $agent->{host};

# Endpoint to retrieve contract IDs
my $contracts_endpoint = "$baseurl/papi/v1/contracts";
my $contracts_resp = $agent->get($contracts_endpoint);
die "Error retrieving contract ID: " . $contracts_resp->status_line unless $contracts_resp->is_success;
my $contracts_data = decode_json($contracts_resp->decoded_content);
my @contract_ids = map { $_->{contractId} } @{ $contracts_data->{contracts}->{items} };

# Endpoint to retrieve group IDs
my $groups_endpoint = "$baseurl/papi/v1/groups";
my $groups_resp = $agent->get($groups_endpoint);
die "Error retrieving group ID: " . $groups_resp->status_line unless $groups_resp->is_success;
my $groups_data = decode_json($groups_resp->decoded_content);
my @group_ids = map { $_->{groupId} } @{ $groups_data->{groups}->{items} };

# Process all combinations of contract IDs and group IDs
foreach my $contract_id (@contract_ids) {
    foreach my $group_id (@group_ids) {
        my $properties_endpoint = "$baseurl/papi/v1/properties?contractId=$contract_id&groupId=$group_id";
        my $properties_resp = $agent->get($properties_endpoint);

        if ($properties_resp->is_success) {
            # Retrieve property information
            my $properties_data = decode_json($properties_resp->decoded_content);
            my $properties = $properties_data->{properties}->{items};

            foreach my $property (@$properties) {
                my $property_id = $property->{propertyId};
                my $property_name = $property->{propertyName};

                # Create a directory for the property
                my $base_dir = "property";
                my $property_dir = File::Spec->catdir($base_dir, $property_name);
                make_path($property_dir) unless -d $property_dir;

                # Retrieve activated version information
                my $activations_endpoint = "$baseurl/papi/v1/properties/$property_id/activations?contractId=$contract_id&groupId=$group_id";
                my $activations_resp = $agent->get($activations_endpoint);

                if ($activations_resp->is_success) {
                    my $activations_data = decode_json($activations_resp->decoded_content);

                    # Sort activations to get the latest active versions for STAGING and PRODUCTION
                    my ($staging_version, $production_version);
                    foreach my $activation (sort { $b->{propertyVersion} <=> $a->{propertyVersion} } @{ $activations_data->{activations}->{items} }) {
                        if (!defined $staging_version && $activation->{network} eq 'STAGING' && $activation->{status} eq 'ACTIVE') {
                            $staging_version = $activation->{propertyVersion};
                        }
                        if (!defined $production_version && $activation->{network} eq 'PRODUCTION' && $activation->{status} eq 'ACTIVE') {
                            $production_version = $activation->{propertyVersion};
                        }
                    }

                    # If no active version found, skip to the next property
                    unless (defined $staging_version || defined $production_version) {
                        warn "No active version found for property ($property_name) - Skipping\n";
                        next;
                    }

                    # Retrieve and save staging version details if an active version is found
                    if (defined $staging_version) {
                        my $staging_rules_endpoint = "$baseurl/papi/v1/properties/$property_id/versions/$staging_version/rules?contractId=$contract_id&groupId=$group_id";
                        my $staging_rules_resp = $agent->get($staging_rules_endpoint);

                        if ($staging_rules_resp->is_success) {
                            my $staging_rules_content = $staging_rules_resp->decoded_content;
                            my $staging_file_path = File::Spec->catfile($property_dir, "staging.json");

                            open my $fh, '>', $staging_file_path or die "Failed to create file: $staging_file_path";
                            print $fh $staging_rules_content;
                            close $fh;

                            print "Saved staging environment active property details: $staging_file_path\n";
                        } else {
                            warn "Error retrieving staging version details ($property_name): " . $staging_rules_resp->status_line . " - Skipping\n";
                        }
                    }

                    # Retrieve and save production version details if an active version is found
                    if (defined $production_version) {
                        my $production_rules_endpoint = "$baseurl/papi/v1/properties/$property_id/versions/$production_version/rules?contractId=$contract_id&groupId=$group_id";
                        my $production_rules_resp = $agent->get($production_rules_endpoint);

                        if ($production_rules_resp->is_success) {
                            my $production_rules_content = $production_rules_resp->decoded_content;
                            my $production_file_path = File::Spec->catfile($property_dir, "production.json");

                            open my $fh, '>', $production_file_path or die "Failed to create file: $production_file_path";
                            print $fh $production_rules_content;
                            close $fh;

                            print "Saved production environment active property details: $production_file_path\n";
                        } else {
                            warn "Error retrieving production version details ($property_name): " . $production_rules_resp->status_line . " - Skipping\n";
                        }
                    }
                } else {
                    warn "Error retrieving activation information ($property_name): " . $activations_resp->status_line . " - Skipping\n";
                }
            }
        } elsif ($properties_resp->code == 403 || $properties_resp->code == 404) {
            warn "Error retrieving property list (Contract ID: $contract_id, Group ID: $group_id): " . $properties_resp->status_line . " - Skipping\n";
        } else {
            die "Unexpected error (Contract ID: $contract_id, Group ID: $group_id): " . $properties_resp->status_line;
        }
    }
}
