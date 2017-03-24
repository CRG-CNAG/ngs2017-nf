#!/bin/bash
set -e 
set -u 

X_TYPE=${1:-t2.large}
X_AMI=${2:-ami-7da1921b}
X_SUBNET=${3:-subnet-05222a43} 

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
    printf "    \b\b\b\b"
}

echo "~~ N G S '1 7  -  W O R K S H O P ~~" 
echo "" 
echo "Launching EC2 virtual machine" 
echo "- ami   : $X_AMI" 
echo "- type  : $X_TYPE" 
echo "- subnet: $X_SUBNET"
echo ""

# Ask for confirmation 
read -u 1 -p "* Please confirm you want to launch an VM with these settings [y/n] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then echo ABORTED; exit 1; fi

# Launch a Ec2 instance  
OUT=$(aws ec2 run-instances --image-id $X_AMI --instance-type $X_TYPE --subnet-id $X_SUBNET --output text)

X_ID=$(echo "$OUT" | grep INSTANCES | cut -f 8)
X_STATE=$(echo "$OUT" | grep STATE | head -n 1 | cut -f 3) 
echo  ""
echo "* Instance launched >> $X_ID <<"  
echo -n "* Waiting for ready status .. "
spinner $$ &

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

# Done
echo ""
echo ""
echo "* The instance is ready -- Login with the following command:" 
echo "" 
echo "  ssh ngs17@$X_IP"
echo "  (password \`ngs17\`)" 
echo ""
