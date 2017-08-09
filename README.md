# ps-flexlm
Powershell FlexLM wrapper

This is a small Powershell wrapper to make it easier to get structured license usage data out of a given FlexLM server. I've been trying to recreate the debug log for data, but found that restarts and other environmental interruptions can create a flawed dataset. Instead, I'll try polling the service directly and just parse all the content.

There's a couple other FlexLM parsers out there, notibly written in Python, but I thought one that uses Powershell would be a little more my speed.

Now that I am re-reading through my code comments, I seem to have been a little angry when I wrote the core functions. 
