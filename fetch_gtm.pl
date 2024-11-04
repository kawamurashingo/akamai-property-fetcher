use strict;
use warnings;
use Akamai::Edgegrid;
use JSON;
use File::Spec;
use File::Path 'make_path';
use Parallel::ForkManager;

# Initialize the Akamai::Edgegrid agent by reading credentials from the .edgerc file
my $agent = Akamai::Edgegrid->new(
    config_file => "$ENV{HOME}/.edgerc",
    section     => "default"
);

# Set the base URL for the GTM API
my $baseurl = "https://" . $agent->{host};

# Set the number of parallel processes
my $max_processes = 4;
my $pm = Parallel::ForkManager->new($max_processes);

# Endpoint to retrieve GTM domains
my $gtm_domains_endpoint = "$baseurl/config-gtm/v1/domains";
my $gtm_domains_resp = $agent->get($gtm_domains_endpoint);
die "Error retrieving GTM domains: " . $gtm_domains_resp->status_line unless $gtm_domains_resp->is_success;
my $gtm_domains_data = decode_json($gtm_domains_resp->decoded_content);
my @gtm_domains = @{ $gtm_domains_data->{items} };

foreach my $domain (@gtm_domains) {
    my $domain_name = $domain->{name};
    my $gtm_properties_endpoint = "$baseurl/config-gtm/v1/domains/$domain_name/properties";
    my $properties_resp = $agent->get($gtm_properties_endpoint);

    if ($properties_resp->is_success) {
        my $properties_data = decode_json($properties_resp->decoded_content);
        my @properties = @{ $properties_data->{items} };

        foreach my $property (@properties) {
            # Fork a new process for each property
            $pm->start and next;

            my $property_name = $property->{name};

            # Create a directory for the domain and property
            my $base_dir = "gtm_config";
            my $property_dir = File::Spec->catdir($base_dir, $domain_name, $property_name);
            make_path($property_dir) unless -d $property_dir;

            # Retrieve full property configuration
            my $property_config_endpoint = "$baseurl/config-gtm/v1/domains/$domain_name/properties/$property_name";
            my $property_config_resp = $agent->get($property_config_endpoint);

            if ($property_config_resp->is_success) {
                my $property_config_content = $property_config_resp->decoded_content;
                my $property_file_path = File::Spec->catfile($property_dir, "config.json");

                open my $fh, '>', $property_file_path or die "Failed to create file: $property_file_path";
                print $fh $property_config_content;
                close $fh;

                print "Saved GTM property configuration: $property_file_path\n";
            } else {
                warn "Error retrieving GTM property details ($property_name): " . $property_config_resp->status_line . " - Skipping\n";
            }

            # End the child process
            $pm->finish;
        }
    } else {
        warn "Error retrieving GTM properties for domain $domain_name: " . $properties_resp->status_line . " - Skipping\n";
    }
}

# Wait for all child processes to finish
$pm->wait_all_children;
