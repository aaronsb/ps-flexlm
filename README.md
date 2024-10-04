# ps-flexlm
# Powershell FlexLM Wrapper

This repository contains a Powershell wrapper designed to simplify the process of retrieving structured license usage data from a FlexLM server. 

## Overview

FlexLM servers can sometimes produce flawed datasets due to restarts and other environmental interruptions. Additionally, Flexera offers the option to encrypt logging data, which can only be decrypted using their proprietary tools. This wrapper aims to bypass these issues by polling the service directly and parsing the content.

## Features

- **Direct Polling**: Bypasses the need for decrypted log files by polling the FlexLM service directly.
- **Powershell Implementation**: A Powershell-based solution for those who prefer it over other languages like Python.
- **Elasticsearch Export**: Includes an example for exporting FlexLM data to Elasticsearch as a set of usage terms. The returned objects contain more data than what is pushed into Elasticsearch, allowing for further customization.

## Motivation

While there are other FlexLM parsers available, most are written in Python. This project provides a Powershell alternative that may be more suitable for users comfortable with that environment.

## Usage

### Prerequisites

- Powershell 5.1 or later
- FlexLM server
- `flexlm_monitor.xml` configuration file

### Setup

To get started with the Powershell FlexLM Wrapper, follow these steps:

1. **Clone the repository:**
    First, you need to clone the repository to your local machine. Open your terminal and run the following commands:
    ```sh
    git clone https://github.com/yourusername/ps-flexlm.git
    cd ps-flexlm
    ```

2. **Configuration File:**
    Ensure that the `flexlm_monitor.xml` configuration file is in the same directory as the script. This file contains the necessary configuration settings for the FlexLM services you want to monitor. If you don't have this file, you may need to create it based on the example provided in the repository or obtain it from your FlexLM server administrator.

3. **FlexLM Binary:**
    Make sure the `lmstat` binary is available on your system. This binary is required to communicate with the FlexLM server and retrieve license usage data. The `lmstat` binary is typically included with the FlexLM server installation. Ensure that the directory containing `lmstat` is included in your system's PATH environment variable, or provide the full path to the binary in your script.

4. **Powershell Version:**
    Verify that you have Powershell 5.1 or later installed on your system. You can check your Powershell version by running the following command in your Powershell terminal:
    ```powershell
    $PSVersionTable.PSVersion
    ```
    If you need to install or update Powershell, follow the instructions on the [official Powershell documentation](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell).

By following these steps, you will have the necessary setup to use the Powershell FlexLM Wrapper and start retrieving license usage data from your FlexLM server.

### Functions

#### Get-FlexLMStat

Retrieves the status of licenses from the FlexLM server.

**Usage:**
```powershell
Get-FlexLMStat -Port <PortNumber> -LMHost <Hostname>
```

#### Get-FlexLMServices

Lists all FlexLM services defined in the `flexlm_monitor.xml` file.

**Usage:**
```powershell
Get-FlexLMServices
```

#### Get-FlexLMStatHost

Retrieves the status of licenses for a specific service.

**Usage:**
```powershell
Get-FlexLMStatHost -ServiceName <ServiceName>
```

#### Export-FlexLMFeaturesToELS

Exports the FlexLM feature data to an Elasticsearch instance.

**Usage:**
```powershell
Export-FlexLMFeaturesToELS -ServiceName <ServiceName> [-doit] [-urlroot <URLRoot>]
```

### Example

To retrieve the status of licenses from a FlexLM server running on port 27000 at `flexlm.example.com`:
```powershell
Get-FlexLMStat -Port 27000 -LMHost flexlm.example.com
```

To export the feature data to Elasticsearch:
```powershell
Export-FlexLMFeaturesToELS -ServiceName MyService -doit
```

This will push the data to the Elasticsearch instance defined in the `flexlm_monitor.xml` file.

