
### How To Incorporate the 'macOS Security Compliance Project' Into Jamf Pro

In this document I will show how to use the NIST tool chain with the CIS level 2 benchmark. You can find the tools at `https://github.com/usnistgov/macos_security`. The method will work with any other baseline in the project, just replace `cis_lvl2` everywhere below with the name of the baseline you want to use.

#### Grab the Tools

Go in to whatever directory you store your git repositories and `git clone git@github.com:usnistgov/macos_security` to pull down the latest version of the toolset

#### Before You Build

To do this properly you should communicate with your Security team exactly what you are doing. The first step is to print the entire set of security rules in the benchmark. To do this you create a PDF by running the guidance script on the base YAML file. Go into the top level of the repo and ...
```
~/macos_security $ ./scripts/generate_guidance.py baselines/cis_lvl2.yaml
```
You will then see:
```
Profile YAML: baselines/cis_lvl2.yaml
Output path: /Users/puck/work/macos_security/build/cis_lvl2/cis_lvl2.adoc
Generating HTML file from AsciiDoc...
Generating PDF file from AsciiDoc...
```
Now there will be a PDF file in `build/cis_lvl2` called `cis_lvl2.pdf`

Go through this file and write down the rule number and title for all the rules you don't think are needed in your organisation. At my company we decided "7.21 Enable Show All Filename Extensions" would confuse users. There may be others, CIS level 2 is a tight benchmark.

Take this list and the PDF file and get Security to check if they are fine with your changes to the baseline.

#### Now On To Building

Once you have finished that argument (I hope without too much bloodshed) take the file `cis_lvl2_yaml` and copy it to the custom directory with a new name that tells you it is yours:
```
~/macos_security $ cp baselines/cis_lvl2.yaml custom/cis_lvl2_puck.yaml
```

Open the copy and comment all the lines for the rules you don't want (put '# ' at the start of the line). For our example rule, the line containing `os_show_filename_extensions_enable`.

We now run the generate guidance script. Point it at the changed YAML file and add arguments to generate the config profiles (`-p`) and the compliance script  (`-s`).
```
$ scripts/generate_guidance.py -p -s custom/cis_lvl2_puck.yaml
```

This will generate a new directory inside `build` with the name of your YAML file. Inside is a directory containing the mobileconfig profiles, the compliance script, the documentation files, and a folder "preferences" that we can safely ignore.

```
$ ls build/cis_lvl2_puck/
puck.adoc          cis_lvl2_puck.html          cis_lvl2_puck.pdf           
cis_lvl2_puck_compliance.sh                    mobileconfigs                  preferences
```

### Implementation

##### Some Tedious Stuff

Now we are ready to start in on our Jamf Pro set up. I assume I don't need to tell you to do all this on your test instance not production.

First step is to create a category for all our scripts, policies and profiles. Mine is `CIS v2`. Also create a Computer Group called CIS v2 TEST and scope everything to that group; profiles, policies, the lot. Assign a test Mac or two to that group.

Now we are going to create a configuration profile that sets everything we can set in the Jamf GUI. I call mine `0.0 CIS2 Monterey Restrictions`

Open the file `cis_lvl2_puck.pdf` in Preview. Go through all the rules and where possible set them in our profile. All of section 6 can be skipped over but right off the bat `7.1 Disable Airdrop` can be set in the `Restrictions` payload of our profile.  Go through the rest one by one. Don't worry right now about any rules you can't set.

Now go through the rules a second time.

Some of the rules you can't set it in the Jamf GUI but you can set with a custom settings upload. For these create a separate config profile titled with the number and name of the rule. 

An example of this would be the rule I have, "7.06 Enable Firewall Logging". You can see in the "Remediation Description" that we should create a config profile and the payload is `com.apple.security.firewall`. Look in the directory `build\cis_lvl2_puck\mobileconfigs\preferences` for a file with the same name as the payload. Create the profile "7.0.6 Enable Firewall Logging" and in the section "Application & Custom Settings" add an "Upload". The "Preference Domain" is the name of our file (minus the ".plist") and the contents of the file is copied in to the "Property List" field. Save the profile.

This is the last of the truly tedious stuff.

##### The Script

We are almost ready to upload our script. We need to remove some code in the compliance script as it incorrectly checks the number of command line arguments:
```
# check for command line arguments, if --check or --fix, then just do them.
if (( # >= 2));then
    echo "Too many arguments. Usage: $0 [--check| --fix]"
    exit 1
fi
```

They are just above the only call to the `zparseopts` function.

 (It is entirely possible that by this time the lines have been removed from the git repo for you so if you don't see them don't worry.)

Now go create a script in Jamf Pro. This can be found under Settings > Computer Management > Scripts > New Script.
 - Use the General pane to configure basic settings for the script, including the display name and assign to our previously created category.
- Use the Script pane to paste in our compliance script “cis_lvl2_puck_compliance.sh".
- Use the Options pane to set the Parameter 4 label to `Options (--check, --fix, --stats, --compliant, --non_compliant)`.
##### _The 'Options' pane of our script_
![Script](script.png =600x)
##### More Pieces

Next we create two Extension Attributes in Jamf Pro, one to count the non-compliant rules and one to list them. This can be found under Settings > Computer Management. In the “Computer Management–Management Framework” section, click Extension Attributes  > New.

- Set the Data type to String
- Set the Input type to Script
- Paste into the script section in the editor and save
```
#!/bin/zsh

# cis v2 - Audit List

echo "<result>"
/usr/libexec/PlistBuddy -c "Print" /Library/Preferences/org.cis_lvl2_puck.audit.plist |\
 grep -B 1 "finding = true"`
echo "</result>"
```
- Set the Data type to Integer
- Set the Input type to Script
- Paste the script section in the editor and save
```
#!/bin/zsh

# cis v2 - Audit Count

echo "<result>"
/usr/libexec/PlistBuddy -c "Print" /Library/Preferences/org.cis_lvl2_puck.audit.plist |\
  grep -c "finding = true"
echo "</result>"
```

It should be said that the compliance script contains a method for finding the count of non-compliant and compliant rules that is much more complex than the one above. I have yet to discover a reason for that.

Now for a Smart Group that looks at the audit count.
- Name: CIS v2 - Non-compliant
- Criteria: EA cis v2 - Audit Count > 0

##### Policies

We want three policies. The first one run is "CISv2 Fix". It runs at enrollment complete and with a custom trigger of `cis_fix`. Then we have "CISv2 Check" which runs at Check-in and has a custom trigger of `cis_check`. These two policies run the compliance script. One with `--check` in the options while the other has `--fix`

Our final policy, "CISv2 Fix Controller", runs at Check-in and is scoped to "CIS v2 Non-compliant". This policy runs a script:
```
 #!/bin/zsh

# v1.0 2020-04-29 ARW

# write to fix log
echo $(date) >> /Library/Management/cisfixlog.txt
/usr/libexec/PlistBuddy -c "Print" /Library/Preferences/org.cis_lvl2_puck.audit.plist | \
	grep -B 1 "finding = true" ) >> /Library/Management/cisfixlog.txt
    
# do the fix
jamf policy -event cis_fix ; 

# do a recheck to pick up the remediation
jamf policy -event cis_check

# do a recon to update the EAs
jamf recon
```

In my SOE I use `/Library/Management` as a place for all the bits and pieces I use such as the  company logo. If you use a different spot use that.

The first half of the script logs the date and a list of the non-compliant rules to a text file. We can read `/Library/Management/cisfixlog.txt` in an EA if we want. Having this makes security happy as you are logging every breach.

The second half is running `jamf` three times. You can see that we run the remediation, then run the check again. This check *should* pick up that the Mac is now compliant and write that out to our audit plist. Now a `jamf recon` will update our two EAs by making them run again. That means the Mac is no longer a member of our smart group.
##### Testing

For preliminary testing I turn on Self Service for the three policies. I also edit any other security policies and set them to exclude our test group, we want to be sure we get a clean test.

To do our testing we want a rule that is easily broken and just as easily fixed but doesn't constitute a large breach of security. "Disable Root Login" is the perfect candidate. `/usr/bin/dscl . -create /Users/root UserShell /bin/zsh` will break it and the remediation done by our system is a single line `/usr/bin/dscl . -create /Users/root UserShell /usr/bin/false`.

One note in testing is that the policy log is only written after a policy completes so even though "CISv2 Fix Control" runs first it will be above "CISv2 Fix" and "CISv2 Check" in the Policy Log.

Once you have got it working by running the policies via self service in your test instance find some volunteers to run the system in production to make sure you're not breaking something with all the new security rules. If you are then figure out which rule it is and go back to Security.

##### Caveat

In our organisation we use FileVault (as everyone should). This causes a problem with the first check on enrollment as it runs before the Mac reboots and enables FileVault. This gives us a non-compliance that shouldn't be there. At the moment I use a brute force method to fix this. I take out the FileVault rule and treat it separately. I am attempting to find a better solution, if you think of one I would love to hear it.

##### What About That Preference File?

What file? Oh, *that* preference file. That is the file `org.cis_lvl2_puck.audit.plist`. Before we go too far let me point out that when you have the system all installed and running you will have **two** files with the same name. One in `/Library/Preferences` which holds the **output** of the compliance script and one in `/Library/ManagedPreferences` which will be the preference file **for** the compliance script.

It is the second one we are talking about now.

This preference file is for 'special cases'. It has a list of all the rules and a key `exempt` which is false unless we want to exempt that rule where we change the key to true. Here is what a rule looks like:
```
	<key>sysprefs_automatic_login_disable</key>
	<dict>
		<key>exempt</key>
		<false/>
	</dict>
```

What if we had a number of Mac Minis used as an XCode build cluster. They're hiding in a server room without monitors or keyboards so it might be safe to power them up and log in automatically after a power outage. So we change that `<false/>` to `<true/>` and upload the preference file exactly the same way we did other config profiles. Scope that preference file to the build Minis and we have handled our 'special case'
