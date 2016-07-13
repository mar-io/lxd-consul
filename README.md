# lxd-consul

Want to experiment with Consul clusters or LXD containers? Look no further.

lxd-consul is a bash script that will spin up a consul cluster on Ubuntu 16.04 LTS utilizing lxd containers.

This script will start a 3 node consul cluster using LXD containers running Alpine Linux. Each node takes about 9MB space so its very lightweight and fast. Furthermore, the consul cluster data will persist if the system or container reboots without needing to create data mounts.

lxd-consul has only been tested on Ubuntu 16.04 and should be used for dev/testing purposes.

#### Prerequisites
* Ubuntu 16.04 LTS

* LXD install -- [howto](https://linuxcontainers.org/lxd/getting-started-cli/)

#### Installing lxd-consul

Clone the repo:
`git clone git@github.com:badmadrad/lxd-consul.git`

Change Directory:
`cd lxd-consul`

**Run** the script:
`./lxd-consul.sh create`

At this point, the script will run, create containers, and return the IPs of the cluster.

To **stop** the cluster:

`./lxd-consul.sh stop`

To **start** the cluster:

`./lxd-consul.sh start`

To **destroy** the cluster:

`./lxd-consul.sh destroy`

When you reboot your computer or need to re-bootstrap the consul cluster simply run **a restart**:

`./lxd-consul.sh restart`

This will bring your cluster back and the data should still be persisted.

#### Why LXD instead of Docker?

LXD is a very easy to use/install virtualization solution for Ubuntu users. With LXD you get all the benefits of Docker like speed, portability, isolation, and performance. However, you gain a more familiar hypervisor experience as opposed to the somewhat opinionated Docker workflow. LXD is designed to run containers which are running full operating systems which allow you to treat the container like a vm. LXD containers are smaller than traditional VM images and since they are containers they run very close to the metal. For this script, I utilized Alpine OS images which are extraordinarily minimalist images using about 3MB of disk. Only potential downside is that LXD doesn't have a declarative configuration file (Dockerfile) or as great a mindshare/ecosystem as Docker.

#### Further Reading

I highly recommend reading about the ease and benefits of LXD here:
[LXD Tutorial](http://insights.ubuntu.com/2016/03/14/the-lxd-2-0-story-prologue/)
