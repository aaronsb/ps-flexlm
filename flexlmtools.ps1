<#
.SYNOPSIS
    Retrieves the status of licenses from the FlexLM server.

.DESCRIPTION
    The Get-FlexLMStat function polls the FlexLM server to retrieve the status of licenses. 
    It processes the raw data returned by the server and structures it into a more readable format.
    Note: The lmstat utility is required to pull the data from the FlexLM server. Ensure that lmstat is installed and accessible in your system's PATH.

.PARAMETER Port
    The port number on which the FlexLM server is running.

.PARAMETER LMHost
    The hostname of the FlexLM server.

.EXAMPLE
    Get-FlexLMStat -Port 27000 -LMHost flexlm.example.com

    This command retrieves the status of licenses from the FlexLM server running on port 27000 at flexlm.example.com.

.NOTES
    Ensure that the flexlm_monitor.xml configuration file is in the same directory as the script.

.LINK
    https://github.com/aaronsb/ps-flexlm
#>
function Get-FlexLMStat {
    param ([int]$Port, $LMHost)
    $erroractionpreference = "SilentlyContinue"
    #extracting this from the toolbox environment this used to live in so it works "standalone"..ish.
    $Config = [xml](Get-Content ("flexlm_monitor.xml"))
    function PrivGetRegex {
        param($FilterName)
        $config.PSFlexLM.RegExLibrary.Filter | Where-Object { $_.id -eq $FilterName } | ForEach-Object { $_.'#text' }
    }
    function PrivProcessLMDateString {
        param ($LMDateString)
        if (!$LMDateString) {
            $DateObject = ""
        }
        else {
            $rgxFloatSeatDateTime = '(^\w+) (\w+)\/(\w+) (\w+:\w+)'
            # FlexLM uses unconventional date formats. The date "1-jan-0" represents a non-expiring license.
            if ($LMDateString -eq "1-jan-0") {
                $DateObject = Get-Date "1/1/2000"
            }
            else {
                try {
                    $DateObject = [datetime]$LMDateString
                }
                catch {
                    # Note: The year is not required in the date format.
                    # The time is in 24-hour format for consistency.
                    # This section is separated for clarity and readability.
                    $DateRaw = ($LMDateString | Select-String $rgxFloatSeatDateTime).Matches.Groups.Value
                    $DateObject = Get-Date (("{0:D2}" -f [int]$DateRaw[2]) + "/" + ("{0:D2}" -f [int]$DateRaw[3]) + "/" + (Get-Date).Year + " " + $DateRaw[4])    
                }
            }
        }
        $DateObject
    }

    #region Execute lmstat command to retrieve the license status information from the FlexLM server
    $LMStatData = Invoke-Expression ($config.PSFlexLM.Configuration.LMUtilPath + " lmstat -c $Port@$LMHost -a")
    
    #region Define all the regular expression objects. Consider integrating these directly into the filter operations for improved maintainability in the future.
    $rgxLicenseServer = (PrivGetRegex ServerStatus)
    $rgxFeatureUse = (PrivGetRegex FeatureUseOverview)
    $rgxBulkFloatData = (PrivGetRegex FloatingLicensePrefilter)
    $rgxFloatFeatureParse = (PrivGetRegex FloatingLicenseFeatureSummary)
    $rgxFloatSeatConsumption = (PrivGetRegex FloatingLicenseFeatureDetail)
    
    $ServerStatus = $LMStatData | Select-String $rgxLicenseServer
    $FeatureStatus = $LMStatData | Select-String $rgxFeatureUse
    $FloatingFeatureData = ($LMStatData | Select-String $rgxBulkFloatData).Line
    
    #region build server status hashtable
    $StatusHash = [PSCustomObject]@{"Hostname" = $ServerStatus.Matches.Groups[1].Value; "Status" = $ServerStatus.Matches.Groups[2].Value }

    #region build featurehashtable
    $FeatureHash = New-Object System.Collections.Generic.List[System.Object]
    foreach ($feature in $FeatureStatus) {
        $FeatureHash.Add([PSCustomObject]@{"FeatureName" = $feature.Matches.Groups[1].Value;
                "Issued"                                 = $feature.Matches.Groups[2].Value;
                "Consumed"                               = $feature.Matches.Groups[3].Value;
                "Available"                              = ($feature.Matches.Groups[2].Value - $feature.Matches.Groups[3].Value);
                "FloatingFeatureStatus"                  = New-Object System.Collections.Generic.List[System.Object]
            })
    }



    #region build floating feature detail hash table
    $FloatingFeatureHash = New-Object System.Collections.Generic.List[System.Object]
    $i = 0
    do {
        do {
            if ($floatingFeatureData[$i].IndexOf("    ") -eq -1) {   
                $header = $null
                $guid = [guid]::NewGuid()
                #-1 means header. this is a header line. Parse data.
                $header = $floatingFeatureData[$i] | Select-String $rgxFloatFeatureParse
                    
                $FloatingFeatureHash.Add([PSCustomObject]@{"guid" = $guid
                        "FloatingFeatureName"                     = $header.Matches.Groups.Value[1];
                        "FeatureVersion"                          = $header.Matches.Groups.Value[2];
                        "VendorDaemon"                            = $header.Matches.Groups.Value[3];
                        "FeatureExpiry"                           = PrivProcessLMDateString $header.Matches.Groups.Value[4];
                        "SeatConsumptionData"                     = New-Object System.Collections.Generic.List[System.Object]
                    })
            }
            else {
                $data = $null
                #0 means data. this is a data line. Parse data.
                $data = $floatingFeatureData[$i] | Select-String $rgxFloatSeatConsumption
                   
                #$floatingLicenseUse = $data.Matches.Groups.Value
                   
                $floatingLicenseUse = [PSCustomObject]@{"Username" = $data.Matches.Groups.Value[1];
                    "LicenseLoanedHost"                            = $data.Matches.Groups.Value[2];
                    "Version"                                      = $data.Matches.Groups.Value[3];
                    "LicenseManagerHost"                           = $data.Matches.Groups.Value[4];
                    "LicenseManagerHostTCPPort"                    = $data.Matches.Groups.Value[5];
                    "ThisIsProbablyImportantToo"                   = $data.Matches.Groups.Value[6];
                    "DateAction"                                   = $data.Matches.Groups.Value[7];
                    "Date"                                         = PrivProcessLMDateString $data.Matches.Groups.Value[8]
                }
                                                            
                    ($FloatingFeatureHash | Where-Object { $guid -eq $_.Guid }).SeatConsumptionData.Add($floatingLicenseUse)
            }$i++   
        }
        Until (($FloatingFeatureData[$i].IndexOf("    ") -eq -1) -or $FloatingFeatureData.Length -eq $i)
    }
    Until ($i -ge [int]$FloatingFeatureData.Length)

    #region insert floating features into overall feature state
    foreach ($FloatingFeature in $FloatingFeatureHash) {
        foreach ($Feature in $FeatureHash) {
            if ($FloatingFeature.FloatingFeatureName -eq $Feature.FeatureName) {
                $Feature.FloatingFeatureStatus.Add(($FloatingFeature | Select-Object -Property FeatureVersion, VendorDaemon, FeatureExpiry, SeatConsumptionData))
            }
        }
    }
    @{"FeatureState" = $FeatureHash; "ServerState" = $StatusHash; "FloatingState" = $FloatingFeatureHash }
    
}


function Get-FlexLMServices {
    #extracting this from the toolbox environment this used to live in so it works "standalone"..ish.
    #$Config = [xml](Get-Content ($env:toolboxxml + "\etc\flexlm_monitor.xml"))
    $Config = [xml](Get-Content ("flexlm_monitor.xml"))
    $config.PSFlexLM.Servers.Daemon
}


function Get-FlexLMStatHost {
    param($ServiceName)
    #extracting this from the toolbox environment this used to live in so it works "standalone"..ish.
    #$Config = [xml](Get-Content ($env:toolboxxml + "\etc\flexlm_monitor.xml"))
    $Config = [xml](Get-Content ("flexlm_monitor.xml"))


    foreach ($daemon in $config.PSFlexLM.Servers.Daemon) {
        if ($daemon.id -match $ServiceName) {
            Get-FlexLMStat -Port $daemon.TCPPort -LMHost $daemon.hostname
        }
        
    }
}

function Export-FlexLMFeaturesToELS {
    param($serviceName, [switch]$doit, $urlroot = "http://elk.contoso.com:9199")
    $StatObject = Get-FlexLMServices $serviceName
    $Config = [xml](Get-Content ("flexlm_monitor.xml"))
    $urlroot = $Config.PSFlexLM.Elastic.Host
    
    #mappings
    $ELSMappings = '{
        "mappings": {
            "FeatureName": {
                "properties": {
                    "Available": {
                        "type": "integer"
                    },
                    "Issued": {
                        "type": "integer"
                    },
                    "Consumed": {
                        "type": "integer"
                    }
                }
            }
        }
    }'
    #end mappings

    if (!$StatObject) {
        write-error "No Stat object found by that name."
        break
    }
    #configure flexlm index in els
    $elk_index = ("flexlm_" + $serviceName)
    $elk_type = "feature"
    $features = $StatObject.FeatureState | Select-Object "FeatureName", "Issued", "Consumed", "Available"
    $features | Add-Member -MemberType NoteProperty -Name "@timestamp" -value ""
    $features | ForEach-Object { $_."@timestamp" = $StatObject.ServerState.DateTime }
    #each feature is a type stored in an index.

    #verify index (and mapping exists). If not, create the initial index and the mapping.
    try {
        $els_index_config = Invoke-RestMethod -Method Get -Uri ($urlroot + "/" + $elk_index)
    }
    catch {
        #error thrown, probably a missing index config, so try making a new one.
        Invoke-RestMethod -Method PUT -Uri ($urlroot + "/" + $elk_index) -ContentType "application/json" -Body $ELSMappings | Out-Null
    }
    #reverify index mappings after add.

    $els_index_config = Invoke-RestMethod -Method Get -Uri ($urlroot + "/" + $elk_index)
    if (!$els_index_config.$elk_index.mappings.FeatureName.properties) {
        try {
            write-warning "Existing index found without mappings. Trying to add mappings."
            Invoke-RestMethod -Method PUT -Uri ($urlroot + "/" + $elk_index) -ContentType "application/json" -Body $ELSMappings | Out-Null
            write-debug "Attemping to create new index mappings for $elk_index"
        }
        catch {
            write-error $error[0]
            throw "Couldn't add ELS mappings for flexlm indicies."
        }
    }
    else {
        write-debug "Found index mappings for $elk_index"
    }
    
    $uri = ($urlroot + "/" + $elk_index + "/" + $elk_type)
    foreach ($item in $features) {
        $body = ($item | Select-Object "FeatureName", "Issued", "Consumed", "Available", "@timestamp") | ConvertTo-Json -Compress
        if ($doit) {
            Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json' -Body $body | Out-Null    
        }
        else {
            "$body $uri"
        }
    }
}