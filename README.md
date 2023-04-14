# VM-Series Active/Passive HA on Google Cloud

This tutorial creates a pair of Active/Passive VM-Series firewalls on Google Cloud.   This architecture provides the following benefits:
* Configuration sync between the VM-Series firewalls.
* State synchronization between instances to maintain state on failover.


The autoscale architecture is recommended in most use-cases.  Please see [VM-Series on Google Cloud](https://cloud.google.com/architecture/partners/palo-alto-networks-ngfw) for more information on VM-Series deployment models.


## Architecture

This deployment model provides solutions for the following key use-cases:

* IPSec termination of site-to-site VPNs.
* Legacy applications that need visibility of the original source client IP (No SNAT solution) for inbound traffic flows.
* Requirements for session fail-over on failure of VM-Series.

![Overview Diagram](images/diagram.png)

## Prepare for deployment

1. Enable the required APIs, generate an SSH key, and clone the repository. 

    ```
    gcloud services enable compute.googleapis.com
    ssh-keygen -f ~/.ssh/vmseries-tutorial -t rsa
    git clone https://github.com/PaloAltoNetworks/google-cloud-vmseries-ha-tutorial
    cd google-cloud-vmseries-ha-tutorial
    ```

2. Create a `terraform.tfvars` file.

    ```
    cp terraform.tfvars.example terraform.tfvars
    ```

3. Edit the `terraform.tfvars` file and set values for the following variables:

    | Variable      | Description                                    |
    |-----------------|----------------------------------------------------------------------------------|
    | `project_id `     | Set to your Google Cloud deployment project.                                     |
    | `public_key_path` | Set to match the full path you created previously.                               |
    | `mgmt_allow_ips`  | Set to a list of IPv4 ranges that can access the VM-Series management interface. |
    | `prefix`          | (Optional) If set, this string will be prepended to the created resources.       |
    | `vmseries_image_name`          | (Optional) Defines the VM-Series image to deploy.  A full list of images can be found [here](https://docs.paloaltonetworks.com/vm-series/11-0/vm-series-deployment/set-up-the-vm-series-firewall-on-google-cloud-platform/deploy-vm-series-on-gcp/use-custom-templates-or-the-gcloud-cli-to-deploy-the-vm-series-firewall).       |

4. (Optional) If you are using BYOL image (i.e. `vmseries-flex-byol-*`), the license can be applied during deployment by adding your VM-Series authcode to `bootstrap_files/authcodes`.
5. Save your `terraform.tfvars` file.


## Deployment
When no further changes are necessary in the configuration, deploy the resources:

1. Initialize and apply the Terraform plan.  

    ```
    terraform init
    terraform apply
    ```

2. Enter `yes` to start the deployment.
   
3. After all the resources are created, Terraform displays the following message:

    ```
    Apply complete!

    Outputs:

    EXTERNAL_LB_IP    = "ssh paloalto@1.1.1.1 -i ~/.ssh/vmseries-tutorial"
    EXTERNAL_LB_URL    = "https://1.1.1.1"
    VMSERIES_ACTIVE    = "https://2.2.2.2"
    VMSERIES_PASSIVE   = "https://3.3.3.3"
    ```

## Test the deployment

We can now test the deployment by accessing the `workload-vm` that resides in the trust VPC network.  All of the `workload-vm` traffic is routed directly through the VM-Series HA pair. 

1. Use the output `EXTERNAL_LB_URL` to access the web service on the `workload-vm` through the VM-Series firewall.

    <img src="images/web.png" width="500">

2. Use the output `EXTERNAL_LB_SSH`  to open an SSH session through the VM-Series to the `workload-vm`.  
    ```
    ssh paloalto@1.1.1.1 -i ~/.ssh/vmseries-tutorial
    ```

3. On the workload VM, run a preloaded script to test the failover mechanism across the VM-Series firewalls.
    ```
    /network-check.sh
    ```

    You will see output like this where `x.x.x.x` is the IP address is `EXTERNAL_LB_IP` address.
    ```
    Wed Mar 12 16:40:18 UTC 2023 -- Online -- Source IP = x.x.x.x
    Wed Mar 12 16:40:19 UTC 2023 -- Online -- Source IP = x.x.x.x
    Wed Mar 12 16:40:20 UTC 2023 -- Online -- Source IP = x.x.x.x
    Wed Mar 12 16:40:21 UTC 2023 -- Online -- Source IP = x.x.x.x
    ```

4. Login to the VM-Series firewalls using the `VMSERIES_ACTIVE` and `VMSERIES_PASSIVE` output values.
    ```
    UN: admin
    PW: Pal0Alt0@123 
    ```

5. After login, take note of the HA Status in the bottom right corner on each firewall.

    <b>Active Firewall</b></br>
    <img src="images/image1.png" width="350">

    <b>Passive Firewall</b></br>
    <img src="images/image2.png" width="350">

6. Perform a user initiated failover.
   1. On the ***Active Firewall***, go to the **Device → High Availability → Operational Commands**.
   2. Click **Suspend local device for high availability**.
        <img src="images/image3.png" width="630">
   3. When prompted, click **OK** to initiate the failover.</br>
        <img src="images/image4.png" width="285">


7. You should notice your SSH session to the `workload-vm` is still active.  This indicates the session successfully failed over between the VM-Series firewalls.  The script output should also display the same source IP address.
    ```
    Wed Mar 12 16:47:18 UTC 2023 -- Online -- Source IP = x.x.x.x
    Wed Mar 12 16:47:19 UTC 2023 -- Online -- Source IP = x.x.x.x
    Wed Mar 12 16:47:21 UTC 2023 -- Offline
    Wed Mar 12 16:47:22 UTC 2023 -- Offline
    Wed Mar 12 16:47:23 UTC 2023 -- Online -- Source IP = x.x.x.x
    Wed Mar 12 16:47:24 UTC 2023 -- Online -- Source IP = x.x.x.x
    ```

## (Optional) Onboard Internet Applications
You can onboard and secure multiple internet facing applications through the VM-Series firewall.  This is done by mapping forwarding rules on the external load balancer to NAT policies defined on the VM-Series firewall.

1. In Cloud Shell, deploy a virtual machine into a subnet within the trust VPC network.  The virtual machine in this example runs a sample application for you.
   ```
    gcloud compute instances create my-app2 \
        --network-interface subnet="panw-us-central1-trust",no-address \
        --zone=us-central1-a \
        --image-project=panw-gcp-team-testing \
        --image=ubuntu-2004-lts-apache-ac \
        --machine-type=f1-micro
   ```

2. Record the `INTERNAL_IP` address of the new virtual machine.
    ```
    NAME: my-app2
    ZONE: us-central1-a
    MACHINE_TYPE: f1-micro
    PREEMPTIBLE:
    INTERNAL_IP: 10.0.2.4
    EXTERNAL_IP:
    STATUS: RUNNING
    ```

3. Create a new forwarding rule on the external TCP load balancer. 
    ```
    gcloud compute forwarding-rules create panw-vmseries-extlb-rule2 \
        --load-balancing-scheme=EXTERNAL \
        --region=us-central1 \
        --ip-protocol=L3_DEFAULT \
        --ports=ALL \
        --backend-service=panw-vmseries-extlb
    ```

4.  Retrieve and record the address of the new forwarding rule.
    ```
    gcloud compute forwarding-rules describe panw-vmseries-extlb-rule2 \
        --region=us-central1 \
        --format='get(IPAddress)'
    ```

    (output)
    ```
    34.172.143.223
    ```

5. On the active VM-Series, go to **Policies → NAT**.  Click **Add** and enter a name for the rule.

6. Configure the **Original Packet** as follows:
   1. **Source Zone**: `untrust`
   2. **Destination Zone**: `untrust`
   3. **Service**: `service-http`
   4. **Destination Address**:  Set to the forwarding rule's IP address (i.e. `34.172.143.223`).
        <img src="images/nat1.png" width="630">

7. In the **Translated Packet** tab, configure the **Destination Address Translation** as follows:
   1. **Translated Type**: `Static IP`
   2. **Translated Address**: Set to the `INTERNAL_IP` of the sample application (i.e. `10.0.2.4`). 
        <img src="images/nat2.png" width="630">

8. Click **OK** and Commit the changes.
9. Access the sample application using the forwarding rule's address.
    ```
    http://34.172.143.223
    ```
    <img src="images/image5.png" width="400">



## Clean up

To avoid incurring charges to your Google Cloud account for the resources you created in this tutorial, delete all the resources when you no longer need them.

1. (Optional) If you onboarded an additional application, delete the forwarding rule and sample application machine. 
    ```
    gcloud compute forwarding-rules delete panw-vmseries-extlb-rule2 \
        --region=us-central1

    gcloud compute instances delete my-app2 \
        --zone=us-central1-a
    ```

2. Run the following command.
    ```
    terraform destroy
    ```

3. At the prompt to perform the actions, enter `yes`. 
   
   After all the resources are deleted, Terraform displays the following message:

    ```
    Destroy complete!
    ```

## Additional information

* Learn about the[ VM-Series on Google Cloud](https://docs.paloaltonetworks.com/vm-series/10-2/vm-series-deployment/set-up-the-vm-series-firewall-on-google-cloud-platform/about-the-vm-series-firewall-on-google-cloud-platform).
* Getting started with [Palo Alto Networks PAN-OS](https://docs.paloaltonetworks.com/pan-os). 
* Read about [securing Google Cloud Networks with the VM-Series](https://cloud.google.com/architecture/partners/palo-alto-networks-ngfw).
* Learn about [VM-Series licensing on all platforms](https://docs.paloaltonetworks.com/vm-series/10-2/vm-series-deployment/license-the-vm-series-firewall/vm-series-firewall-licensing.html#id8fea514c-0d85-457f-b53c-d6d6193df07c).
* Use the [VM-Series Terraform modules for Google Cloud](https://registry.terraform.io/modules/PaloAltoNetworks/vmseries-modules/google/latest). 