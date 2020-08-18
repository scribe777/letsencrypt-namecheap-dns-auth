#!/bin/sh

####### !!!!!!!!!!!!!  W A R N I N G !!!!!!!!!!!!! ####### 
#
#  NameCheap only has an API for setting all host DNS records
#  i.e., we can't simply update one TXT row
#
# That forces the workflow of this script to:
#	first read in all host records,
#	leave out any old _acme-challenge records
#	add our new certbot _acme-challenge record
#	REPLACE ALL HOST DNS RECORDS
#
# This sounds dangerous and probably is!  I took a screenshot
# of my existing NameCheap DNS entries before running this script
# in case it didn't preserve something.
# I personally wouldn't trust my script on a domain which had
# more than 10 records.  This means the update URL gets pretty long
# and AGAIN WANT TO ENCOURAGE YOU TO TAKE A SCREENSHOT OF YOUR DNS
# CONFIGURATION AND CHECK IT AFTER RUNNING THIS SCRIPT
#
# ALSO, NameCheap recommends creating a sandbox account and
# testing there.  I would suggest doing this.
# You can run this script directly, instead of from certbot
# if you fill in a couple extra variables, as mentioned in
# the SANDBOX section below.

# QuickStart: Don't quickstart.  Read everything up to this point first.
#	You'll need the wget and dig commands available
#	Enable API access on your NameCheap Account and obtain your APIKey
#	Whitelist the IP of the server from where you will run this script
#	Configure this script with your NameCheap userID, APIKey, and whitelisted IP address
#
#	TEST THIS SCRIPT BY CONFIGURING IT TO A SANDBOX ACCOUNT YOU'VE SETUP AT: https://ap.www.sandbox.namecheap.com/
#	(see SANDBOX section below)
#
#	provide this script to certbox-2 when renewing, e.g.,
#	certbot-2 renew --manual-auth-hook=/root/letsencrypt-namecheap-dns-auth.sh
#
#	Probably put the above command in a monthly cron job
#
# Best wishes,
#	Troy A. Griffitts <scribe@crosswire.org>
#	https://crosswire.org
#

#
# START OF SCARY SCRIPT ----------------------------------------------------
#
# -------  certbot will pass us these variables -------
#
# CERTBOT_DOMAIN: The domain being authenticated
# CERTBOT_VALIDATION: The validation string
# CERTBOT_TOKEN: Resource name part of the HTTP-01 challenge (HTTP-01 only)
# CERTBOT_REMAINING_CHALLENGES: Number of challenges remaining after the current challenge
# CERTBOT_ALL_DOMAINS: A comma-separated list of all domains challenged for the current

# NameCheap's production API service base
SERVICEURL="https://api.namecheap.com/xml.response"


# --------------- Start configurable section --------------------------------

# your NameCheap login ID
# (their docs mention both API User and NC User, but they are the same
# in our scenario because we are editing our own records and not one of our 'clients')
NCUSER=myUserID

# your whitelisted IP address
CLIENTIP=8.8.8.8

# your API Key
NCAPIKEY=9zzzzzzzzzzzzzzzzzzzzzzzzzzzzzf4

#
# SANDBOX TESTING
#
# For sandbox testing first, you'll probably want to override some of these
# then you can just run the script directly and see if you preserve
# all your other host records and get the new acme validation TXT record
# with the dummy value you specify below
#
#SERVICEURL="https://api.sandbox.namecheap.com/xml.response"
#NCAPIKEY=2czzzzzzzzzzzzzzzzzzzzzzzzzzzz1c
#CERTBOT_DOMAIN=crosswire.org
#CERTBOT_VALIDATION=xyzzq


# number of seconds to wait between checks for our certbot validation records to finish propagation
WAITSECONDS=10

# --------------- End configurable section --------------------------------


# Let's grab all our current DNS records

TLD=$(echo ${CERTBOT_DOMAIN} | rev | cut -d. -f1 | rev)
SLD=$(echo ${CERTBOT_DOMAIN} | rev | cut -d. -f2 | rev)


APICOMMAND="namecheap.domains.dns.getHosts&SLD=${SLD}&TLD=${TLD}"
wget -O /tmp/getHosts.xml "${SERVICEURL}?ClientIp=${CLIENTIP}&ApiUser=${NCUSER}&ApiKey=${NCAPIKEY}&UserName=${NCUSER}&Command=${APICOMMAND}"

APICOMMAND="namecheap.domains.dns.setHosts&SLD=${SLD}&TLD=${TLD}"
ENTRYNUM=1;
while IFS= read -r line; do
	NAME=$(echo $line|sed 's/^.* Name="\([^"]*\)".*$/\1/g')
	TYPE=$(echo $line|sed 's/^.* Type="\([^"]*\)".*$/\1/g')
	ADDRESS=$(echo $line|sed 's/^.* Address="\([^"]*\)".*$/\1/g')
	MXPREF=$(echo $line|sed 's/^.* MXPref="\([^"]*\)".*$/\1/g')
	TTL=$(echo $line|sed 's/^.* TTL="\([^"]*\)".*$/\1/g')

	# apparently 1799 is "auto"
	# if we specify what we received in getHosts, we don't preserve 'auto'
	# so we are specifying auto here
	TTL=1799
      
	if [[ "${NAME}" == "_acme-challenge" ]]; then
		# skip all existing _acme-challenge entries
		true
	else
		APICOMMAND="${APICOMMAND}&HostName${ENTRYNUM}=${NAME}&RecordType${ENTRYNUM}=${TYPE}&Address${ENTRYNUM}=${ADDRESS}&MXPref${ENTRYNUM}=${MXPREF}&TTL${ENTRYNUM}=${TTL}"

		ENTRYNUM=$((${ENTRYNUM} + 1))
	fi
done <<< "$(grep "<host " /tmp/getHosts.xml)"


# OK, now let's add our new acme challenge verification record
APICOMMAND="${APICOMMAND}&HostName${ENTRYNUM}=_acme-challenge&RecordType${ENTRYNUM}=TXT&Address${ENTRYNUM}=${CERTBOT_VALIDATION}"

# Finally, we'll update all host DNS records
wget -O /tmp/testapi.out "${SERVICEURL}?ClientIp=${CLIENTIP}&ApiUser=${NCUSER}&ApiKey=${NCAPIKEY}&UserName=${NCUSER}&Command=${APICOMMAND}"

# Actually, FINALLY, we need to wait for out records to propagate before letting certbot continue.
FOUND=false
while [[ "${FOUND}" != "true" ]]; do
echo "Sleeping for ${WAITSECONDS} seconds..."
CURRENT_ACME_VALIDATION=$(dig -t TXT _acme-challenge.${CERTBOT_DOMAIN}|grep "^_acme-challenge.${CERTBOT_DOMAIN}."|cut -d\" -f 2)
if [[ "${CERTBOT_VALIDATION}" == "${CURRENT_ACME_VALIDATION}" ]]; then
	FOUND=true
	echo "Found!"
else
	echo "Not yet found."
fi
done
