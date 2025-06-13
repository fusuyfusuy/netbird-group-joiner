# Netbird Group Manager

A bash script for managing Netbird peer group memberships via CLI. Automatically detects your local peer and provides an interactive interface for joining/leaving groups.

## Features

- **Auto-detection**: Automatically finds your local peer using `netbird status`
- **Interactive UI**: Numbered menus for easy group selection
- **Join Groups**: Add your peer to any available group
- **Leave Groups**: Remove your peer from current groups  
- **Error Handling**: Proper HTTP status checking and error messages
- **Clean Output**: Minimal, focused output with clear status indicators

## Prerequisites

- **Netbird**: Must have netbird client installed and running
- **jq**: JSON processor for parsing API responses
- **curl**: For making HTTP requests to Netbird API
- **Netbird API Token**: Personal access token with group management permissions

## Installation

```bash
git clone https://github.com/fusuyfusuy/netbird-scripts.git
cd netbird-scripts
chmod +x group-joiner.sh
```

## Setup

### 1. Get Your API Token

1. Go to [Netbird Dashboard](https://app.netbird.io)
2. Navigate to **Settings** → **Access Tokens**
3. Create a new **Personal Access Token**
4. Copy the token value

### 2. Set Environment Variable

```bash
export NETBIRD_TOKEN="your_token_here"
```

Or add to your shell profile for persistence:

```bash
echo 'export NETBIRD_TOKEN="your_token_here"' >> ~/.bashrc
source ~/.bashrc
```

## Usage

```bash
./group-joiner.sh
```

### Example Session

```
[+] getting local FQDN...
[+] found FQDN: my-laptop.netbird.cloud
[+] querying netbird API for peers...
[+] parsing peer data...
[+] peer ID: d1573mrl0ubs73f1oh9g (name: my-laptop)
[+] current groups:
   1. All                  (6 peers)
   2. developers           (3 peers)

leave a group? select number (1-2/n): n

[+] available groups:
   1. staging-exit         (2 peers)
   2. production-access    (1 peers)

join a group? select number (1-2/n): 1
[+] joining group: staging-exit (id: d0qds8jl0ubs7392k6fg)
[+] fetching group details...
[+] updating group membership...
[+] successfully joined group: staging-exit
```

## How It Works

1. **Peer Discovery**: Extracts your FQDN from `netbird status -d`
2. **API Query**: Finds your peer ID using the Netbird API
3. **Group Listing**: Shows current groups and available groups
4. **Group Operations**: 
   - **Leave**: Removes your peer ID from group's peers array
   - **Join**: Adds your peer ID to group's peers array
5. **API Updates**: Uses PUT requests to update group configurations

## API Endpoints Used

- `GET /api/peers` - Find local peer information
- `GET /api/groups` - List all available groups  
- `GET /api/groups/{groupId}` - Get specific group details
- `PUT /api/groups/{groupId}` - Update group membership

## Error Handling

The script handles common errors:
- Missing API token
- Netbird not running
- Invalid group selections
- API authentication failures
- Network connectivity issues

## Requirements

- **Bash 4.0+**: For associative arrays
- **jq 1.5+**: For JSON processing
- **curl**: For HTTP requests
- **netbird**: Client must be installed and running

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Security Notes

- **Token Security**: Never commit your API token to version control
- **Permissions**: Use tokens with minimal required permissions
- **Network**: Script makes HTTPS requests to api.netbird.io

## License

MIT License - see LICENSE file for details

## Troubleshooting

### Common Issues

**"NETBIRD_TOKEN environment variable not set"**
```bash
export NETBIRD_TOKEN="your_token_here"
```

**"couldn't extract FQDN from netbird status"**
- Ensure netbird client is running: `netbird status`
- Check if peer is connected to management server

**"HTTP 401/403 errors"**
- Verify API token is valid
- Check token has group management permissions

**"jq: command not found"**
```bash
# Ubuntu/Debian
sudo apt install jq

# macOS
brew install jq

# CentOS/RHEL
sudo yum install jq
```

## Related

- [Netbird Documentation](https://docs.netbird.io)
- [Netbird API Reference](https://docs.netbird.io/api)
- [Netbird GitHub](https://github.com/netbirdio/netbird)