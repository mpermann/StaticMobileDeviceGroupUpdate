#!/bin/bash

# Name: StaticMobileDeviceGroupUpdate.sh
# Date: 04-24-2022
# Author: Michael Permann
# Version: 1.0
# Credits: Inspiration provided by Jamf Nation discussion https://www.jamf.com/jamf-nation/\
# discussions/10471/script-to-add-computers-to-static-group-by-computer-name#responseChild169014
# Purpose: Updates static mobile device group using group name and list of mobile device serial
# numbers. Group name and path to list of serial numbers can be provided as command line arguments
# or they can be provided interactively. If the group doesn't exist, it will be created. Please avoid 
# spaces in file name or paths.
# Usage: StaticMobileDeviceGroupUpdate.sh "Static_Mobile_Device_Group_Name" "/path/to/list/of/serial/numbers"

APIUSER="USERNAME"
APIPASS="PASSWORD"
JPSURL="https://jamf.pro.url:8443"
STATUSCODE="200"
staticGroupName=$1
importList=$2

# Check if command line arguments provided, if not request them interactively
if [ ! "$1" ] || [ ! -f "$2" ]
then
    /bin/echo "Command line arguments not found"
    /bin/echo "Provide static group name"
    read -r -p 'Name: ' staticGroupName
    /bin/echo "$smartGroupName"
    /bin/echo "Provide path to file containing serial numbers"
    read -r -p 'Path to file: ' importList
    /bin/echo "$importList"
fi

staticGroupNameStatusCode=$(/usr/bin/curl -o /dev/null -w "%{http_code}" -s -k -u "$APIUSER":"$APIPASS" "$JPSURL"/JSSResource/mobiledevicegroups/name/"${staticGroupName// /%20}")
/bin/echo "Compare $staticGroupNameStatusCode to $STATUSCODE"
if [ "$staticGroupNameStatusCode" != "$STATUSCODE" ]
then
    /bin/echo "Static group name is $staticGroupName"
    /bin/echo "That doesn't appear to be a valid static group"
    # Create the static group using provided name
    staticGroupID=$(/usr/bin/curl -s -k -u "$APIUSER":"$APIPASS" "$JPSURL"/JSSResource/mobiledevicegroups/id/0 -X POST -H Content-type:application/xml --data "<mobile_device_group><name>$staticGroupName</name><is_smart>false</is_smart><site><id>-1</id><name>None</name></site></mobile_device_group>" | xpath -e /mobile_device_group/id | tr -cd "[:digit:]")
    /bin/echo "$staticGroupName created with ID of: $staticGroupID"
else
    /bin/echo "Group is valid"
    staticGroupID=$(/usr/bin/curl -s -k -u "$APIUSER":"$APIPASS" "$JPSURL"/JSSResource/mobiledevicegroups/name/"${staticGroupName// /%20}" | xpath -e /mobile_device_group/id | tr -cd "[:digit:]")
    /bin/echo "$staticGroupName already exists with ID of: $staticGroupID"
fi
    
# Start creating XML for mobile device group to be uploaded at the end
groupXML="<mobile_device_group><mobile_devices>"

# Read list into an array
inputArrayCounter=0
while read -r line || [[ -n "$line" ]]
do
    inputArray[$inputArrayCounter]="$line"
    inputArrayCounter=$((inputArrayCounter+1))
done < "$importList"
/bin/echo "${#inputArray[@]} lines found"

foundCounter=0
for ((i = 0; i < ${#inputArray[@]}; i++))
do
    /bin/echo "Processing ${inputArray[$i]}"
    serialNumStatusCode=$(/usr/bin/curl -o /dev/null -w "%{http_code}" -s -k -u "$APIUSER":"$APIPASS" "$JPSURL"/JSSResource/mobiledevices/serialnumber/"${inputArray[$i]}")
	/bin/echo "Status code is $serialNumStatusCode"
    if [ "$serialNumStatusCode" = "$STATUSCODE" ]
    then
        groupXML="$groupXML<mobile_device><serial_number>${inputArray[$i]}</serial_number></mobile_device>"
        foundCounter=$((foundCounter+1))
    else
        /bin/echo "${inputArray[$i]} not found" >> "./StaticGroupFailures$staticGroupID.csv"
    fi
done

# Finish creating XML for mobile device group
groupXML="$groupXML</mobile_devices></mobile_device_group>"

# Print final XML
/bin/echo "$groupXML"

# Report on and attempt static group creation
/bin/echo "$foundCounter mobile devices matched"
/bin/echo "Attempting to upload mobile devices to group $staticGroupName"
/usr/bin/curl -s -k -u "$APIUSER":"$APIPASS" "$JPSURL"/JSSResource/mobiledevicegroups/id/"$staticGroupID" -X PUT -H Content-type:application/xml --data "$groupXML"