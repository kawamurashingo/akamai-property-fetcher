# Akamai Property Activation Fetcher

This Perl script retrieves the active staging and production configurations for properties associated with specific contracts and groups on the Akamai platform. The script saves each property’s active configuration in a structured directory format.

## Features

- Fetches active (activated) versions of staging and production configurations for each property.
- Saves configurations in a `property/<property_name>/` directory as `staging.json` and `production.json`.
- Handles multiple contracts and groups, processing all available combinations.
- Provides error handling for cases where access is restricted or configuration retrieval fails.

## Prerequisites

- **Perl**: Ensure Perl is installed on your system.
- **Akamai::Edgegrid**: The script uses the `Akamai::Edgegrid` module for API authentication and access.
- **JSON**: For decoding API responses.
- **File::Spec and File::Path**: For file management and directory creation.

You can install necessary modules using CPAN if they are not already installed:

```bash
cpan install Akamai::Edgegrid JSON File::Spec File::Path
```

## Setup
Authentication

We provide authentication credentials through an API client. Requests to the API are signed with a timestamp and are executed immediately.

    Create authentication credentials[https://techdocs.akamai.com/developer/docs/set-up-authentication-credentials]

    Place your credentials in an EdgeGrid resource file, .edgerc, under a heading of [default] at your local home directory or the home directory of a web-server user.

    [default]
    client_secret = C113nt53KR3TN6N90yVuAgICxIRwsObLi0E67/N8eRN=
    host = akab-h05tnam3wl42son7nktnlnnx-kbob3i3v.luna.akamaiapis.net
    access_token = akab-acc35t0k3nodujqunph3w7hzp7-gtm6ij
    client_token = akab-c113ntt0k3n4qtari252bfxxbsl-yvsdj

1. **Configure .edgerc File**:
   - The script requires an `.edgerc` file in your home directory (`$HOME/.edgerc`) with the necessary Akamai API credentials.
   - Ensure the `.edgerc` file has a section `[default]` with the required access information (host, client_secret, client_token, access_token).

2. **Clone the Repository**:
   ```bash
   git clone https://github.com/yourusername/akamai-property-fetcher.git
   cd akamai-property-fetcher
   ```

3. **Run the Script**:
   Execute the script as follows:
   ```bash
   perl fetch_akamai_properties.pl
   ```

## Usage

The script automatically:
- Fetches available contracts and groups.
- Identifies and retrieves the active configurations for each property in staging and production environments.
- Saves each configuration in JSON format in the `property/<property_name>/` directory.

### Directory Structure

Upon execution, a directory structure similar to the following will be created:

```
property/
├── exampleproperty1.com/
│   ├── staging.json
│   └── production.json
└── exampleproperty2.com/
    ├── staging.json
    └── production.json
```

Each `.json` file contains the rules configuration for the corresponding environment and property.

## Error Handling

- **403 Forbidden**: If access is restricted for a particular contract or group, the script will skip it and continue with the next.
- **404 Not Found**: If a property or version is not found, it will also be skipped.
- **Other Errors**: For any unexpected errors, the script will stop and display an error message.

## License

This project is licensed under the MIT License.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.
