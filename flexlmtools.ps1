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

function Export-FlexLMFeaturesToELS
{param($serviceName,[switch]$doit,$urlroot = "http://elk.contoso.com:9199")
    $StatObject = Get-FlexLMServices $serviceName
    $Config = [xml](gc ("flexlm_monitor.xml"))
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

    if (!$StatObject)
    {
        write-error "No Stat object found by that name."
        break
    }
    #configure flexlm index in els
    $elk_index = ("flexlm_" + $serviceName)
    $elk_type = "feature"
    $features = $StatObject.FeatureState | Select-Object "FeatureName","Issued","Consumed","Available"
    $features | Add-Member -MemberType NoteProperty -Name "@timestamp" -value ""
    $features | %{$_."@timestamp" = $StatObject.ServerState.DateTime}
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
    if (!$els_index_config.$elk_index.mappings.FeatureName.properties)
    {
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
    foreach ($item in $features)
    {
        $body = ($item | Select-Object "FeatureName","Issued","Consumed","Available","@timestamp") | ConvertTo-Json -Compress
        if ($doit)
        {
            Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json' -Body $body | out-null    
        }
        else
        {
            "$body $uri"
        }
    }
}




