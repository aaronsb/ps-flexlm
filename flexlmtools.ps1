function Get-FlexLMStat
{param ([int]$Port,$LMHost)
    $erroractionpreference = "SilentlyContinue"
    #extracting this from the toolbox environment this used to live in so it works "standalone"..ish.
    $Config = [xml](gc ("flexlm_monitor.xml"))
    function PrivGetRegex
    {param($FilterName)
        $config.PSFlexLM.RegExLibrary.Filter | ?{$_.id -eq $FilterName} | %{$_.'#text'}
    }
    function PrivProcessLMDateString
    {param ($LMDateString)
        if (!$LMDateString)
        {
            $DateObject = ""
        }
        else
        {
            $rgxFloatSeatDateTime = '(^\w+) (\w+)\/(\w+) (\w+:\w+)'
            #flexlm hates dates that make sense. What the hell kind of date is 1-jan-0? Oh, that's right. A non-expiring license date.
            if ($LMDateString -eq "1-jan-0")
            {
                $DateObject = Get-Date "1/1/2000"
            }
            else
            {
                try 
                {
                    $DateObject = [datetime]$LMDateString
                }
                catch
                {
                    #Hey, we don't need to include the year!
                            #At least they use 24 hour format for the time.
                            #I put this up here as it's own ugly thing to make it a little more readable.
                    $DateRaw = ($LMDateString | select-string $rgxFloatSeatDateTime).Matches.Groups.Value
                    $DateObject = Get-Date (("{0:D2}" -f [int]$DateRaw[2]) + "/" + ("{0:D2}" -f [int]$DateRaw[3]) + "/" + (Get-Date).Year + " " + $DateRaw[4])    
                }
            }
        }
        $DateObject
    }

    #region call lmstat and get it's text body back
    $LMStatData = iex ($config.PSFlexLM.Configuration.LMUtilPath + " lmstat -c $Port@$LMHost -a")
    
    #region define all the regex objects. maybe roll this into the filter operations themselves in the near future
    $rgxLicenseServer = (PrivGetRegex ServerStatus)
    $rgxFeatureUse = (PrivGetRegex FeatureUseOverview)
    $rgxBulkFloatData = (PrivGetRegex FloatingLicensePrefilter)
    $rgxFloatFeatureParse = (PrivGetRegex FloatingLicenseFeatureSummary)
    $rgxFloatSeatConsumption = (PrivGetRegex FloatingLicenseFeatureDetail)
    
    $ServerStatus = $LMStatData | select-string $rgxLicenseServer
    $FeatureStatus = $LMStatData | select-string $rgxFeatureUse
    $FloatingFeatureData = ($LMStatData | select-string $rgxBulkFloatData).Line
    
    #region build server status hashtable
    $StatusHash = [PSCustomObject]@{"Hostname" = $ServerStatus.Matches.Groups[1].Value;"Status" = $ServerStatus.Matches.Groups[2].Value}

    #region build featurehashtable
    $FeatureHash = New-Object System.Collections.Generic.List[System.Object]
    foreach ($feature in $FeatureStatus)
    {
        $FeatureHash.Add([PSCustomObject]@{"FeatureName" = $feature.Matches.Groups[1].Value;
                            "Issued" = $feature.Matches.Groups[2].Value;
                            "Consumed" = $feature.Matches.Groups[3].Value;
                            "Available" = ($feature.Matches.Groups[2].Value - $feature.Matches.Groups[3].Value);
                            "FloatingFeatureStatus" = New-Object System.Collections.Generic.List[System.Object]})
    }



    #region build floating feature detail hash table
    $FloatingFeatureHash = New-Object System.Collections.Generic.List[System.Object]
    $i=0
    do {
        do {
                if ($floatingFeatureData[$i].IndexOf("    ") -eq -1)
                {   
                    $header = $null
                    $guid = [guid]::NewGuid()
                    #-1 means header. this is a header line. Parse data.
                    $header = $floatingFeatureData[$i] | select-string $rgxFloatFeatureParse
                    
                    $FloatingFeatureHash.Add([PSCustomObject]@{"guid" = $guid
                                                "FloatingFeatureName" = $header.Matches.Groups.Value[1];
                                                "FeatureVersion" = $header.Matches.Groups.Value[2];
                                                "VendorDaemon" = $header.Matches.Groups.Value[3];
                                                "FeatureExpiry" = PrivProcessLMDateString $header.Matches.Groups.Value[4];
                                                "SeatConsumptionData" = New-Object System.Collections.Generic.List[System.Object]})
                }
                else
                {
                    $data = $null
                    #0 means data. this is a data line. Parse data.
                    $data =  $floatingFeatureData[$i] | select-string $rgxFloatSeatConsumption
                   
                    #$floatingLicenseUse = $data.Matches.Groups.Value
                   
                    $floatingLicenseUse = [PSCustomObject]@{"Username" = $data.Matches.Groups.Value[1];
                                                            "LicenseLoanedHost" = $data.Matches.Groups.Value[2];
                                                            "Version" = $data.Matches.Groups.Value[3];
                                                            "LicenseManagerHost" = $data.Matches.Groups.Value[4];
                                                            "LicenseManagerHostTCPPort" = $data.Matches.Groups.Value[5];
                                                            "ThisIsProbablyImportantToo" = $data.Matches.Groups.Value[6];
                                                            "DateAction" = $data.Matches.Groups.Value[7];
                                                            "Date" = PrivProcessLMDateString $data.Matches.Groups.Value[8]}
                                                            
                    ($FloatingFeatureHash | ?{$guid -eq $_.Guid}).SeatConsumptionData.Add($floatingLicenseUse)
                }$i++   
            }
            Until (($FloatingFeatureData[$i].IndexOf("    ") -eq -1) -or $FloatingFeatureData.Length -eq $i)
        }
    Until ($i -ge [int]$FloatingFeatureData.Length)

    #region insert floating features into overall feature state
    foreach ($FloatingFeature in $FloatingFeatureHash)
    {
        foreach ($Feature in $FeatureHash)
        {
            if ($FloatingFeature.FloatingFeatureName -eq $Feature.FeatureName)
            {
                $Feature.FloatingFeatureStatus.Add(($FloatingFeature | Select-Object -Property FeatureVersion,VendorDaemon,FeatureExpiry,SeatConsumptionData))
            }
        }
    }
    @{"FeatureState" = $FeatureHash;"ServerState" = $StatusHash;"FloatingState" = $FloatingFeatureHash}
    
}


function Get-FlexLMServices
{
    #extracting this from the toolbox environment this used to live in so it works "standalone"..ish.
    #$Config = [xml](gc ($env:toolboxxml + "\etc\flexlm_monitor.xml"))
    $Config = [xml](gc ("flexlm_monitor.xml"))
    $config.PSFlexLM.Servers.Daemon
}


function Get-FlexLMStatHost
{param($ServiceName)
    #extracting this from the toolbox environment this used to live in so it works "standalone"..ish.
    #$Config = [xml](gc ($env:toolboxxml + "\etc\flexlm_monitor.xml"))
    $Config = [xml](gc ("flexlm_monitor.xml"))


    foreach ($daemon in $config.PSFlexLM.Servers.Daemon)
    {
        if ($daemon.id -match $ServiceName)
        {
            Get-FlexLMStat -Port $daemon.TCPPort -LMHost $daemon.hostname
        }
        
    }
}
