#!/bin/bash
PROJECT=TTND;BUCKET_INSTALL=LoadTesting_TTND;BUCKET_RESULT=LoadTestingResults_TTND;

sudo apt-get update
sudo apt-get install openjdk-7-jdk --fix-missing -yy

#install jmeter and ant
sudo apt-get install jmeter -y
sudo apt-get install ant -y
sudo apt-get install awscli -y

#remove loopback address from jmeter.properties
sudo sed -i 's/remote_hosts=127/#remote_hosts=127/' /usr/share/jmeter/bin/jmeter.properties

sudo mkdir /usr/share/jmeter/extras

wget https://s3.amazonaws.com/$BUCKET_INSTALL/conversion.xml -O /usr/share/jmeter/extras/conversion.xml
wget https://s3.amazonaws.com/$BUCKET_INSTALL/jmeter-results-detail-report_21.xsl -O /usr/share/jmeter/extras/jmeter-results-detail-report_21.xsl
wget https://s3.amazonaws.com/$BUCKET_INSTALL/File.jmx -O /usr/share/jmeter/extras/File.jmx
wget https://s3.amazonaws.com/$BUCKET_INSTALL/configScriptSlave -O /usr/share/jmeter/extras/configScriptSlave
wget https://s3.amazonaws.com/$BUCKET_INSTALL/slave.sh -O /usr/share/jmeter/extras/slave.sh
wget https://s3.amazonaws.com/$BUCKET_INSTALL/instanceproperties.sh -O /usr/share/jmeter/extras/instanceproperties.sh
wget https://s3.amazonaws.com/$BUCKET_INSTALL/testproperties.sh -O /usr/share/jmeter/extras/testproperties.sh

source /usr/share/jmeter/extras/instanceproperties.sh
source /usr/share/jmeter/extras/testproperties.sh
mkdir ~/.aws
> ~/.aws/config
cat<<here >> ~/.aws/config
[default]
region=us-east-1
output=json
here

>slave.log
IFS=','
array=( $users )

########################## for each iteration
for i in ${array[@]}
do
>/usr/share/jmeter/extras/outputFile_$i.xml
sed -i '/<xslt/d' /usr/share/jmeter/extras/conversion.xml
sed -i '/<project/a <xslt in="/usr/share/jmeter/extras/outputFile_'$i'.xml" out="/usr/share/jmeter/extras/outputFile_'$i'.html"' /usr/share/jmeter/extras/conversion.xml

#create slaves
bash -x /usr/share/jmeter/extras/slave.sh $i
echo "-----------------Please wait while Slaves are configured!--------------------"
sleep 300
source /usr/share/jmeter/extras/testproperties.sh

#read IP of all slaves
IPList=$(cat ip.txt |awk 'FNR==1{print $0}')

##############calculate no of users per slave
UsersPerSlave=`expr $users / $ SlavesNeeded`
R=`expr $users % $SlavesNeeded`
if [ $R -ne 0 ]
then
	UsersPerSlave=`expr $UsersPerSlave + 1`
fi

#run test
jmeter -n -t /usr/share/jmeter/extras/File.jmx -l /usr/share/jmeter/extras/outputFile_"$i".xml -R $IPList -Gusers=$UsersPerSlave;
ant -f /usr/share/jmeter/extras/conversion.xml

#copy result file to S3
aws s3 cp /usr/share/jmeter/extras/outputFile_"$i".html s3://$BUCKET_RESULT/Result/$OutputFile"_"$i".html" --grants read=uri=http://acs.amazonaws.com/groups/global/AllUsers

#check for success threshold
Success=$(grep -o -m 1 '[0-9][0-9]*.[0-9][0-9]%' outputFile_$i.html | cut -d. -f1)
echo "No. of users: "$i
echo "Success Rate: "$Success
echo https://s3.amazonaws.com/$BUCKET_RESULT/$OutputFile"_"$i".html"

if [ $Success -ge $Threshold ]
then
	echo "Executing next test"
else
	echo "Aborting!"
	break
fi
done
echo "-----------------------------------------FINISHED--------------------------------------------------------------"
aws s3 cp /var/log/cloud-init-output.log s3://$BUCKET_RESULT/Logs/jmeter_logs.log --grants read=uri=http://acs.amazonaws.com/groups/global/AllUsers


  
