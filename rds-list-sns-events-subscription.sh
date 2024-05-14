##################################################
# Check if the RDS monitoring has been setup
##################################################

#!/bin/bash

# Function - get current date and time
get_date_time() {
    date +%Y-%m-%d" "%H:%M
}

# Global variables
current_date=$(date +%Y-%m-%d)
full_log="full_log_${current_date}.txt"

>event_subscriptions.csv
>sns_subscriptions.csv
>full_log_${current_date}.txt
>accounts.txt

# Get all active accounts in the organization
for account in $(aws organizations list-accounts --query 'Accounts[?Status==`ACTIVE`].Id' --profile master --output text); do
# for account in 486282677076 311847484087; do 

    echo "$(get_date_time)" | tee -a $full_log
    echo "+------------------------------+" | tee -a $full_log
    echo "Processing account: $account"     | tee -a $full_log
    echo "+------------------------------+" | tee -a $full_log    
       
    # Assume role Terraform
    rolearn="arn:aws:iam::$account:role/Terraform"
    assumed_role=$(aws sts assume-role \
                    --role-arn $rolearn \
                    --role-session-name AssumeRoleSession \
                    --profile master \
                    --query 'Credentials.{AccessKeyId:AccessKeyId,SecretAccessKey:SecretAccessKey,SessionToken:SessionToken}')
    # Set up the credentials
    export AWS_ACCESS_KEY_ID=$(echo $assumed_role | jq -r '.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $assumed_role | jq -r '.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $assumed_role | jq -r '.SessionToken')

	# Check if account role can be assumed
    if [ -z "${assumed_role}" ]; then
        echo "${account} NOK" >> accounts.txt
    else
        echo "${account} OK" >> accounts.txt
	fi
	
	# Get AWS regions
	aws_regions=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)
	
	# Loop to work on all regions
	for region in $aws_regions; do
	# for region in eu-central-1 ap-northeast-1; do
		echo "" | tee -a $full_log
		echo "Processing region: $region" | tee -a $full_log
		
		# Check if region has any SNS subscription
		sns_subscriptions=$(aws sns list-subscriptions \
			--region $region \
			--output text)		
		if [ -z "${sns_subscriptions}" ]; then
			echo "No SNS subscription" | tee -a $full_log
		else            
			# Get SNS subscriptions
			# Write output on the full log file
			aws sns list-subscriptions \
				--region $region \
				--query 'Subscriptions[].[Owner,TopicArn,Endpoint,Protocol]' | tee -a $full_log
			# Write output on the CSV file
			aws sns list-subscriptions \
				--region $region \
				--query 'Subscriptions[].[Owner,TopicArn,Endpoint,Protocol]' \
				--output text > temp.csv
			# Replace tabs with commas
			sed 's/\t/,/g' temp.csv >> sns_subscriptions.csv
		fi

		# Check if region has any RDS Event subscription
		rds_event_subscription=$(aws rds describe-event-subscriptions \
			--region $region \
			--output text)		
		if [ -z "${rds_event_subscription}" ]; then
			echo "No RDS Event subscription" | tee -a $full_log	
		else            
			# Get RDS Event subscriptions
			# Write output on the full log file
			aws rds describe-event-subscriptions \
				--region $region \
				--query 'EventSubscriptionsList[].[CustomerAwsId,CustSubscriptionId,SnsTopicArn,SourceIdsList,EventCategoriesList,Enabled]' | \
				tee -a $full_log
			# Write output on the CSV file
			aws rds describe-event-subscriptions \
				--region $region \
				--query 'EventSubscriptionsList[].[CustomerAwsId,CustSubscriptionId,SnsTopicArn,SourceIdsList,EventCategoriesList,Enabled]' | \
				jq -r '.[] | [.[] | tostring] | @csv' >>event_subscriptions.csv
		fi			
	done
	echo "" | tee -a $full_log

	# Unset assumed role credentials
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
done

# Remove brackets e quotes
sed -i 's/\[//g; s/\]//g; s/"//g' event_subscriptions.csv

# Delete temp CSV files
rm -rf temp.csv


