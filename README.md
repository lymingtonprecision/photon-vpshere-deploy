VMware Photon vSphere Deployment
================================

VMware's [Photon][photon] minimal Linux host distribution is an
excellent platform to deploy containerised infrastructure
to. Unfortunately creating new virtual machines on vSphere using the
distribution is not quite as easy as we'd like.

vSphere provides vApp Options (OVF properties) as a means of providing
run time configuration values to virtual machines. This can be
leveraged to, for example, provide the hostname and network
configuration.

It's particularly useful when coupled with network profiles and IP
pools—enabling you to provision your VMs with a persistent IP address
mapping from a pool of addresses without running a DHCP server.

Sadly (but understandably) Photon has no direct support for OVF
properties. _This_ repository contains scripts, services, and
opinionated instructions for creating a clonable Photon virtual
machine template that can be configured from vApp Options. It
completely removes any requirement to manually configure a virtual
machine running Photon—allowing us to spawn new VMs on a whim.

## Creating the Template VM

Before creating the template you should ensure that the datastores,
folders, networks, and network profiles that you wish to use have been
created in vSphere.

With the vSphere environment configured to your liking the first step
is to create the virtual machine that will be the basis of the
template.

### Preparing a virtual machine to act as the template

1. Download the latest [Photon ISO][photon-iso].
2. Upload the ISO image to a vSphere datastore.
3. Create a new virtual machine

   When selecting the **Guest OS** choose _Linux_ / _Other 3.x Linux
   (64-bit)_.

   Connect the CD/DVD Drive to the ISO from the previous steps.

   You will need to download files to the VM during the configuration
   process so ensure that it is on a network with Internet
   access. Ideally this should be a network with an active DHCP server
   so that you don't need to do any manual configuration.

Power on the virtual machine and connect to its console. You will be
greeted by the Photon installation menu. Choose the **Photon Minimal**
installation and proceed as directed until the installation is
complete and the VM restarts.

After the VM restarts login and, if required, configure the
network.

#### Creating a Temporary Static Network Configuration

If the network you've connected the VM to runs DHCP it should already
have an IP address and you can skip this step, otherwise we'll need to
manually configure a network connection to use during setup.

The simplest way to establish a static network connection is as
follows:

1. At the command prompt enter
   `vim /etc/systemd/network/00-temp.network`
2. Press `i` to enter insert mode and enter (with appropriate
   substitutions):

        [Match]
        Name=eno*

        [Network]
        Address=<ip address>/<CIDR subnet>
        Gateway=<gateway ip>
        DNS=<primary DNS server ip>

3. After entering the network configuration press `ESC` and then enter
   `:wq` to save the file and exit back to the prompt.
4. Run `systemctl restart systemd-networkd.service`
5. Remove the temporary network configuration file
  (`rm /etc/systemd/network/00-temp.network`)

#### Installing the vApp/OVF Scripts

With the VM connected to the network we can proceed to copy over the
scripts needed to use OVF properties. To do this you'll need SSH
access.

1. Enable login over SSH as `root`:

   1. `vim /etc/ssh/sshd_config`
   2. Uncomment the `PermitRootLogin yes` line
   3. Save and close.
   4. Restart the SSH daemon, `systemctl restart sshd`

2. Using an SFTP client copy the `bin` and `lib` directories from this
   project to the `root` user directory in the VM.

3. Revert the change made in step 1 above; we no longer need SSH
   access and leaving it open is insecure.

Back at the VM console we can now install the OVF services, from the
directory to which you copied the `bin` and `lib` directories:

    /bin/sh bin/install-ovf.sh

You can now remove the `bin` and `lib` directories.

#### Miscellaneous Configuration

##### Docker

If you want Docker running by default on any virtual machines you
clone from the template now is a good time to enable it:

    systemctl enable docker

##### DHCP Network Catchall

Photon includes a single `systemd` network configuration file:
`/etc/systemd/network/10-dhcp-en.network` which is ... very open.

To avoid any issues this permissiveness might cause it is recommended
that you either:

* Remove the file completely, if you don't need DHCP network
  configuration.
* Change the `[Match]` section to be less open, i.e. by amending it
  to:

        [Match]
        Name=en*

  This will still enable DHCP configuration of any interfaces you add
  but shouldn't clobber any other network configuration files.

(The specific issue we've seen is a lower priority configuration file
containing a `DNS=` entry being completely ignored when this isn't
changed.)

##### Shell Prompt

You might also want to slightly adjust the default shell prompt to
include the hostname, so that it's easy to tell which VM's console you
are connected to:

1. `vim /etc/bashrc`
2. Enter the substitution: `:%s/\\u/\\u@\\h/g`
3. Save and close (`:wq`)

#### Fini

Shutdown the template virtual machine.

### Configuring the vApp/OVF properties

(Note: if you want the virtual machines to be one a different network
to that used whilst preparing the template you should change it in the
template now.)

Navigate to the virtual machine within the vSphere client and bring up
the settings editor (`Edit Settings...` from the VM summary page or
context menu.)

Disconnect the virtual machines CD/DVD drive by changing it back to
"Client Device.

Change to the "vApp Options" tab, enable vApp options, and configure
the properties that will be sent via OVF depending on your needs:

If you are using a Network Protocol Profile to assign IP addresses
from an address pool then create the properties as below:

* `dns`, the "DNS Servers" dynamic property of your network
* `search-domain`, the "DNS Search Path" dynamic property
* `eth0.ip`, the "IP Address" dynamic property
* `eth0.netmask`, the "Netmask" dynamic property
* `eth0.gw`, the "Gateway" dynamic property

If you are going to manually assign IP addresses when you create the
virtual machines then create the properties as follows:

* User configurable static strings:
  * `dns`, a comma-separated list of DNS server IP addresses
  * `search-domain`, a comma-separated list of search domains
* User configurable static "vApp IP Address"es:
  * `eth0.ip`
  * `eth0.netmask`
  * `eth0.gw`

You can, of course, mix-and-match the above static/dynamic properties
to suit your own environment. You may, for example configure the
`dns`, `search-domain`, `eth0.netmask` and `eth0.gw` dynamically from
a Network Profile but assign the IP addresses manually rather than
from a pool. Use whatever works for you.

Regardless of how you're assigning IP addresses you also need the
following properties:

* `eth0.network`, the "Network Name" dynamic property
* `hostname`, a user configurable static string; this will be where
  you enter the FQDN of each virtual machine when you create them from
  the template.

You also need to adjust some settings in other sections:

* Authoring
  * IP allocation
    * "DHCP" should be ticked
    * "OVF environment" should be ticked
    * "IP protocol" should be "Both"
  * OVF settings
    * "OVF environment transport" must be "VMware Tools"
* Deployment
  * IP allocation
    * Set "IP protocol" to "IPv4"
    * "IP allocation" should match your allocation method: "Static -
      IP Pool" if using an IP pool or "Static - Manual" if not.

With all of that set you should be ready to clone a new virtual
machine! Clone the virtual machine to a template and then proceed to
create clones of it to do "real work".

(Note: you can clone a new virtual machine directly from this
"template" virtual machine—and that can be useful to test that
everything works—but I would recommend cloning it to an actual
template before instantiating any real virtual machine clones from
it. This helps prevent any unintended modification of the template and
ensures that all the virtual machines cloned from it will start off
the same.)

## Instantiating a VM from the Template

1. Navigate to the template within the vSphere client
2. From the available actions on the template select "Deploy VM from
   this Template..."
3. Enter the name of the VM to appear in vSphere and select its
   location
4. Select the compute resource
5. Select the datastore
6. Neither "Customize the operating system" nor its hardware
7. Enter the required vApp parameters. If you are using an IP address
   pool then you will only be prompted to enter the virtual machines
   hostname (FQDN), otherwise you will be prompted for the network
   configuration as well.
8. Done.

Congratulations you should now have a new Photon virtual machine to
play with and—if you are using an IP address pool—the only thing you
had to enter was the hostname.

[photon]: https://github.com/vmware/photon
[photon-iso]: https://bintray.com/vmware/photon/iso/_latestVersion
