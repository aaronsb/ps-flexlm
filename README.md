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
    git clone https://github.com/aaronsb/ps-flexlm.git
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

### Running the Export Process as a Windows Service Every N Minutes

To automate the export of FlexLM feature data to an Elasticsearch instance every 30 minutes (or another desired interval), you can set up a scheduled task on a Windows host using the built-in Task Scheduler. This method will allow you to run the script as a service without manual intervention.

#### Steps to Set Up the Task

1. **Create the PowerShell Script:**
    Ensure the `Export-FlexLMFeaturesToELS` command is wrapped in a PowerShell script that can be executed by Task Scheduler.

    Example script (`ExportFlexLM.ps1`):
    ```powershell
    # Define service name
    $ServiceName = "MyService"

    # Export the FlexLM feature data
    Export-FlexLMFeaturesToELS -ServiceName $ServiceName -doit
    ```

2. **Open Task Scheduler:**
    - Press `Win + R`, type `taskschd.msc`, and press Enter to open Task Scheduler.

3. **Create a New Task:**
    - In the Task Scheduler window, click **Create Task** on the right-hand side.

4. **General Settings:**
    - Under the **General** tab, give your task a name (e.g., "Export FlexLM to ELK").
    - Select **Run whether user is logged on or not** to ensure the task runs in the background.
    - Choose **Run with highest privileges** if required for script execution.

5. **Set the Trigger:**
    - Go to the **Triggers** tab and click **New**.
    - Set the task to begin **On a schedule**.
    - Choose a **Daily** schedule and set the **Repeat task every** option to "30 minutes" (or your desired interval).
    - Ensure the task is set to **Enabled**.

6. **Set the Action:**
    - Go to the **Actions** tab and click **New**.
    - Under **Action**, select **Start a program**.
    - In the **Program/script** field, type `powershell.exe`.
    - In the **Add arguments (optional)** field, provide the path to your script, like this:
    ```powershell
    -ExecutionPolicy Bypass -File "C:\path\to\ExportFlexLM.ps1"
    ```

7. **Conditions and Settings:**
    - In the **Conditions** tab, uncheck **Start the task only if the computer is on AC power** if you want the task to run regardless of power source.
    - Under the **Settings** tab, ensure that **Allow task to be run on demand** is checked, and configure the task to stop if it runs longer than 30 minutes.

8. **Save and Test:**
    - Click **OK** and provide administrative credentials if prompted.
    - You can test the task by right-clicking it in Task Scheduler and selecting **Run**.

This will ensure the FlexLM feature data is exported to your Elasticsearch instance every 30 minutes.