#/bin/bash
#
# Program for PXE configuration
#
#
#
. /root/.colors

clear
echo
echo -e "${Red}******${NC}\t${Green}PROGRAM FOR PXE CONFIGURATION${NC}\t${Red}******${NC}"
echo
echo
echo

#
# Creating temporary folder and files
#
tmp_dir=$(mktemp -d)
cd $tmp_dir
nodes=$(mktemp -p ${tmp_dir})
macs=$(mktemp -p ${tmp_dir})
tmp=$(mktemp -p ${tmp_dir})
all=$(mktemp -p ${tmp_dir})

#
# Populating with data from DHCP
#
cat /etc/dhcp/dhcpd.conf | grep -v ^$ | grep -v ^# | grep host | awk '{print $2}' > $nodes
cat /etc/dhcp/dhcpd.conf | grep -v ^$ | grep -v ^# | grep ethernet | awk '{print $3}' | sed "s/;$//g" > $macs
pr -mt $nodes $macs > $all

#
# Variables for ip addressing calculations
#

dhcp_conf=/etc/dhcp/dhcpd.conf
min_range=$(cat $dhcp_conf | grep range | awk '{print $2}')
max_range=$(cat $dhcp_conf | grep range | awk '{print $3}')
lip=$(cat $dhcp_conf | grep address | tail -1 | awk '{print $2}' | sed "s/;$//")
net=$(echo $lip | cut -d "." -f 1,2,3)
host=$(echo $lip | cut -d "." -f 4)
nhost=$(expr $host + 1)
ip_addr=$net\.$nhost

#
# Function for backing up files
#
bck () {
if [ -z $1 ]
then	
	echo
	echo "No file to bck"
	echo

else
	cp $1 $1.$(date +%H%M-%d%m)
fi 	
}
#
# Function for adding new node
#
add_dhcp () {

bck $dhcp_conf

echo >> $dhcp_conf
echo "host $2 {" >> $dhcp_conf
echo -e "\t\thardware ethernet $1;" >> $dhcp_conf
echo -e "\t\tfixed-address $ip_addr;" >> $dhcp_conf
echo -e '}' >> $dhcp_conf

systemctl restart dhcpd

if [ $? == "0" ]
then
	echo
	echo -e "${Green}DHCPD service configured successfully${NC}"
else
	echo
	echo -e "${Red}Problem with DHCPD configuration${NC}"
fi
}

#
# Function for manipulating DNS server
#
add_dns () {

dnsf=/var/named/db.home.es
dnsi=/var/named/db.192.168.1

new_serial=$(date +%Y%m%d01)
bck $dnsf 
bck $dnsi

echo -e "$2\t\tA\t${ip_addr}" >> $dnsf
serial=$(cat $dnsf | grep serial | awk '{print $1}')
if [ $serial -lt $new_serial ]
then
	sed -e "s/$serial/$new_serial/" $dnsf > $tmp
	\cp $tmp $dnsf
else
	new_serial=$(expr $serial + 1)
	sed -e "s/$serial/$new_serial/" $dnsf > $tmp
	\cp $tmp $dnsf
fi

echo -e "$nhost\tPTR\t$2.home.es" >> $dnsi
serial=$(cat $dnsi | grep serial | awk '{print $1}')
if [ $serial -lt $new_serial ]
then
	sed -e "s/$serial/$new_serial/" $dnsi > $tmp
	\cp $tmp $dnsi
else
	new_serial=$(expr $serial + 1)
	sed -e "s/$serial/$new_serial/" $dnsi > $tmp
	\cp $tmp $dnsi
fi

$(which rndc) reload &>/dev/null
if [ $? == "0" ]
then	
	echo 
	echo -e "${Green}Reload of DNS successful${NC}"
else
	echo
	echo -e "${Red}There was a problem wit DNS reloading${NC}"
	exit 1
fi
}

#
# Removing all temp staff
#
remove () {

if [ -d $tmp_dir ]
then
	echo
	echo -e "${Red}Removing all temporary staff...${NC}"
	rm -rf $tmp_dir
else
	echo 
fi
}

#
# Getting input from user
#
PS3=$(echo -e "\n${Blue}Select an option:${NC}")
select var in "Add a file with nodes" "List nodes in DHCP conf file" "Add a new node" "Force node to boot from local disk" "Exit"
do
	case "$var" in
		"Add a file with nodes" )
			echo "Enter file path. Format: mac_address name per line"
			read path
			if [ -s $path ]
			then
				for line in $(cat $path)
				do
					add_dhcp $(awk '{print $1}' $line) $(awk '{print $2}' $line)
					add_dns $(awk '{print $1}' $line) $(awk '{print $2}' $line)
				done
			else
				echo
				echo -e "${Red}File $path does not exist${NC}"
				remove
				sleep 1
				clear
				exit 1
			fi
		;;
		"List nodes in DHCP conf file" )
			echo
			cat $all
			echo
		;;
		"Add a new node" )
			echo "Enter new node MAC address. Format: 00:00:00:00:00:00"
			read addr
			if [ -z $addr ]
			then
				echo "Please enter a valid address."
				remove
				sleep 1
				clear
				exit 1
			else
				echo "Enter new node name"
				read name
				add_dhcp $addr $name
				add_dns $addr $name
			fi
		;;
		"Force node to boot from local disk" )
			echo "Enter MAC address in lowercase. Format: 00-00-00-00-00-00"
			read addr
			cp /var/lib/tftpboot/pxelinux.cfg/local_disk_boot /var/lib/tftpboot/pxelinux.cfg/01-$addr
		;;
		"Exit" )
			echo
			remove
			echo -e "${Red}Exiting...${NC}"
			sleep 1
			clear
			exit 0
		;;
	esac
done
