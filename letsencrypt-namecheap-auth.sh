#!/bin/sh

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
NCUSER=scribe777

# your whitelisted IP address
CLIENTIP=209.250.6.226

# your API Key
NCAPIKEY=94072ba1d5054c75a05c3ff845ad6ef4

# number of seconds to wait between checks for our certbot validation records to finish propagation
WAITSECONDS=10

# For sandbox testing first, you'll probably want to override some of these
# then you can just run the script directly and see if you preserve
# all your other host records and get the new acme validation TXT record
# with the dummy value you specify below
#
#SERVICEURL="https://api.sandbox.namecheap.com/xml.response"
#NCAPIKEY=2cac3aee097f4bc08a9b4776e2e6401c
#CERTBOT_DOMAIN=crosswire.com
#CERTBOT_VALIDATION=xyzzq


# --------------- End configurable section --------------------------------


# Let's grab all our current DNS records

TLD=$(echo ${CERTBOT_DOMAIN} | rev | cut -d. -f1 | rev)
SLD=$(echo ${CERTBOT_DOMAIN} | rev | cut -d. -f2 | rev)


APICOMMAND="namecheap.domains.dns.getHosts&SLD=${SLD}&TLD=${TLD}"
wget -O getHosts.xml "${SERVICEURL}?ClientIp=${CLIENTIP}&ApiUser=${NCUSER}&ApiKey=${NCAPIKEY}&UserName=${NCUSER}&Command=${APICOMMAND}"

APICOMMAND="namecheap.domains.dns.setHosts&SLD=${SLD}&TLD=${TLD}"
ENTRYNUM=1;
while IFS= read -r line; do
	NAME=$(echo $line|sed 's/^.* Name="\([^"]*\)".*$/\1/g')
	TYPE=$(echo $line|sed 's/^.* Type="\([^"]*\)".*$/\1/g')
	ADDRESS=$(echo $line|sed 's/^.* Address="\([^"]*\)".*$/\1/g')
	MXPREF=$(echo $line|sed 's/^.* MXPref="\([^"]*\)".*$/\1/g')
	TTL=$(echo $line|sed 's/^.* TTL="\([^"]*\)".*$/\1/g')
      
	if [[ "${NAME}" == "_acme-challenge" ]]; then
		# skip all existing _acme-challenge entries
		true
	else
		# we're leaving off the TTL entry here and letting them all be auto; if we specify what we received, we don't preserve 'auto'
		APICOMMAND="${APICOMMAND}&HostName${ENTRYNUM}=${NAME}&RecordType${ENTRYNUM}=${TYPE}&Address${ENTRYNUM}=${ADDRESS}&MXPref${ENTRYNUM}=${MXPREF}"

		ENTRYNUM=$((${ENTRYNUM} + 1))
	fi
done <<< "$(grep "<host " getHosts.xml)"


# OK, now let's add our new acme challenge verification record
APICOMMAND="${APICOMMAND}&HostName${ENTRYNUM}=_acme-challenge&RecordType${ENTRYNUM}=TXT&Address${ENTRYNUM}=${CERTBOT_VALIDATION}"

# Finally, we'll update all host DNS records
wget -O testapi.out "${SERVICEURL}?ClientIp=${CLIENTIP}&ApiUser=${NCUSER}&ApiKey=${NCAPIKEY}&UserName=${NCUSER}&Command=${APICOMMAND}"

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
