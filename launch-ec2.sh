#!/bin/bash
set -e 
set -u 

X_TYPE=${1:-t2.large}
X_AMI=${2:-ami-61d0ec07}
X_DISK=${3:-8}
X_SUBNET=${4:-subnet-05222a43} 

function getRootDevice() {
  local ami=$1
  local size=$2

  local str="$(aws ec2 describe-images --image-ids $ami --query 'Images[*].{ID:BlockDeviceMappings}' --output text)"
  local device=$(echo "$str" | grep ID | cut -f 2)
  local delete=$(echo "$str" | grep EBS | cut -f 2 | tr '[:upper:]' '[:lower:]')
  local snapsh=$(echo "$str" | grep EBS | cut -f 4)
  local type=$(echo "$str" | grep EBS | cut -f 6)

cat << EndOfString
{
    "DeviceName": "$device",
    "Ebs": {
        "DeleteOnTermination": $delete,
        "SnapshotId": "$snapsh",
        "VolumeSize": $size,
        "VolumeType": "$type"
    }
}
EndOfString

}

function spinner() {
    local pid=$1
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    #printf "    \b\b\b\b"
}

echo "~~ N G S '1 7  -  W O R K S H O P ~~" 
echo "" 
echo "Launching EC2 virtual machine" 
echo "- type  : $X_TYPE" 
echo "- ami   : $X_AMI" 
echo "- disk  : $X_DISK GB"
echo "- subnet: $X_SUBNET"
echo ""

# Ask for confirmation 
read -u 1 -p "* Please confirm you want to launch an VM with these settings [y/n] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then echo ABORTED; exit 1; fi

# Launch a Ec2 instance  
OUT=$(aws ec2 run-instances --image-id $X_AMI --instance-type $X_TYPE --subnet-id $X_SUBNET --block-device-mappings "[$(getRootDevice $X_AMI $X_DISK)]" --output text)

X_ID=$(echo "$OUT" | grep INSTANCES | cut -f 8)
X_STATE=$(echo "$OUT" | grep STATE | head -n 1 | cut -f 3) 
echo  ""
echo "* Instance launched >> $X_ID <<"  
echo -n "* Waiting for ready status .. "
(spinner $$ 2>/dev/null)&
spinner_pid=$!

# tag the instance 
aws ec2 create-tags --resources $X_ID --tags Key=Name,Value="User: $(hostname)"

# Wait for instance in `running` status
while [ $X_STATE = pending ]; do 
    sleep 5
    OUT=$(aws ec2 describe-instances --instance-ids $X_ID --output text)
    X_STATE=$(echo "$OUT" | grep STATE | cut -f 3)   
done

if [ $X_STATE != running ]; then
  echo "* Oops .. something went wrong :("
  echo ""
  echo "$OUT"
  exit 1
fi 
  
# Fetch the publish host name   
X_IP=$(echo "$OUT" | grep ASSOCIATION | head -n 1 | cut -f 3)

# Probe SSH connection until it's avalable 
X_READY=''
while [ ! $X_READY ]; do
    sleep 10
    set +e
    OUT=$(ssh -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o BatchMode=yes ec2-user@$X_IP 2>&1 | grep 'Permission denied' )
    [[ $? = 0 ]] && X_READY='ready'
    set -e
done 

kill $spinner_pid &>/dev/null

# Done
echo ""
echo ""
echo "* The instance is ready -- Login with the following command:" 
echo "" 
echo "  ssh ngs17@$X_IP"
echo "  (password \`ngs17\`)" 
echo ""
