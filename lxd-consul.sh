#!/usr/bin/env bash

# DISCLAIMER: Only use for development or testing purposes. Only tested on Ubuntu 16.04 LTS.
# AUTHOR: Mario Harvey https://marioharvey.com

# set consul version
consul_version='0.6.4'

# set alpine os version
alpine_version='3.4'

# container names
names=(consul1 consul2 consul3)

command_exists () {
    type "$1" &> /dev/null ;
}

user="$(id -un 2>/dev/null || true)"

  if [ "$user" != 'root' ]; then
    if command_exists sudo; then
      sh_c='sudo -E sh -c'
    elif command_exists su; then
      sh_c='su -c'
    else
      cat >&2 <<-'EOF'
      Error: this script requires root or sudo as it will install wget and unzip if it doesn't exist.
      We are unable to find either "sudo" or "su" available to make this happen.
EOF
      exit 1
    fi
  fi

get_consul_ip(){
	/usr/bin/lxc info "$1" | grep 'eth0:\sinet\s' | awk 'NR == 1 { print $3 }'
}

check_agent(){
	  /usr/bin/lxc exec "$1" -- ps -ef | grep 'consul\sagent' > /dev/null 2>&1
}

get_all_ips(){
  x=0
  echo 'getting IPs for Consul containers...'
  #get the ip for consul bootstrap instance
  while [ -z "$bootstrap_ip" -o -z "$consul2_ip" -o -z "$consul3_ip" ]
    do
      if [ "$x" -gt 30 ]; then echo 'Cannot get an IPs for the consul instances. Please check lxd bridge and try again. Cleaning...'; destroy; exit 2; fi
      bootstrap_ip=$(get_consul_ip "${names[0]}")
      consul2_ip=$(get_consul_ip "${names[1]}")
      consul3_ip=$(get_consul_ip "${names[2]}")
      ((x++))
      sleep 2
  done
}

check_one_ip(){
  x=0
  echo 'getting IPs for Consul containers...'
  #get the ip for consul bootstrap instance
  while [ -z "$ip" ]
    do
      if [ "$x" -gt 30 ]; then echo 'Cannot get an IPs for the consul instances. Please check lxd bridge and try again. Cleaning...'; destroy; exit 2; fi
      ip=$(get_consul_ip "$1")
      ((x++))
      sleep 2
  done
}

output(){
	echo '              lxd-consul setup complete!           '
	echo '***************************************************'
	echo '                    consul ui links                ' 
	echo "             * http://$bootstrap_ip:8500           "
	echo "             * http://$consul2_ip:8500             "
	echo "             * http://$consul3_ip:8500             "
	echo '***************************************************'
}

start(){
	echo 'starting consul containers...'
	/usr/bin/lxc start "${names[0]}" "${names[1]}" "${names[2]}"
	if [ $? -gt 0 ]; then echo 'want a consul cluster? run: ./lxd-consul.sh create!'; exit 1; fi
    get_all_ips
    echo 'bringing up consul bootstrap container...'
    /usr/bin/lxc exec "${names[0]}" -- rc-service consul-bootstrap start > /dev/null 2>&1
    echo 'restarting consul server containers...'
    /usr/bin/lxc exec "${names[1]}" -- rc-service consul-server restart > /dev/null 2>&1
    /usr/bin/lxc exec "${names[2]}" -- rc-service consul-server restart > /dev/null 2>&1
	output
}

stop(){
	echo 'stopping consul containers...'
	/usr/bin/lxc exec "${names[0]}" -- rc-service consul-server stop > /dev/null 2>&1
	/usr/bin/lxc exec "${names[0]}"-- rc-service consul-server stop > /dev/null 2>&1
	/usr/bin/lxc exec "${names[0]}" -- rc-service consul-bootstrap stop > /dev/null 2>&1
	/usr/bin/lxc exec "${names[0]}"-- rc-service consul-server stop > /dev/null 2>&1
	/usr/bin/lxc stop "${names[0]}" "${names[1]}" "${names[2]}" > /dev/null 2>&1
}

restart(){
	echo 'restarting consul containers...'
	stop
	start
}

destroy(){
	echo 'destroying lxd-consul cluster...'
	# stopping cluster
    stop
	# delete containers
	echo 'deleting consul containers...'
	/usr/bin/lxc delete -f "${names[0]}" "${names[1]}" "${names[2]}"

	echo 'lxd-consul destroyed!'
}

create(){
  #check if containers exist and are already running consul
  i=0
  for name in "${names[@]}";
    do
       # if constainer exists start it
       if /usr/bin/lxc info "$name" > /dev/null 2>&1; then
       	/usr/bin/lxc start "$name" > /dev/null 2>&1
       	check_one_ip "$name"  > /dev/null 2>&1
       	/usr/bin/lxc exec "$name" -- rc-service consul-server start > /dev/null 2>&1
       fi
       # check for running consul agents
       if check_agent "$name" > /dev/null 2>&1; then
       	echo "$name is already running with consul agent!"
       	((i++))
       fi
  done

  if [ "$i" -eq 3 ]; then
  	echo 'Consul cluster already running on lxd containers.'
  	echo 'You can restart or stop with ./lxd-consul.sh restart/stop'
  	echo "Usage: $0 command {options:create,destroy,start,stop,restart}"
  	exit 1
  fi

  # check if lxc client is installed. if not exit out and tell to install
  if command_exists lxc; then
  	echo 'lxc client appears to be there. Proceeding with cluster creation...'
  	sleep 1
  else
  	echo 'lxd does not appear to be installed properly. Follow instructions here: https://linuxcontainers.org/lxd/getting-started-cli'
  fi

  if ! command_exists wget || ! command_exists unzip; then
    # istall packages required
    $sh_c "apt update && apt install unzip wget -y"
  fi

  # download consul and extract into directory
  /usr/bin/wget https://releases.hashicorp.com/consul/$consul_version/consul_"$consul_version"_linux_amd64.zip -O "consul_$consul_version.zip"
  /usr/bin/unzip -o "consul_$consul_version.zip"
  /bin/rm "consul_$consul_version.zip"
  
  # get base lxd image
  echo "copying down base Alpine $alpine_version image..."
  /usr/bin/lxc image copy images:alpine/$alpine_version/amd64 local: --alias=alpine$alpine_version
  
  for name in "${names[@]}";
    do
      # create containers
      /usr/bin/lxc launch alpine$alpine_version "$name" -c security.privileged=true
      # make consul dirs
      /usr/bin/lxc exec "$name" -- mkdir -p /consul/data
      /usr/bin/lxc exec "$name" -- mkdir -p /consul/server
      # move consul binary into containers
      /usr/bin/lxc file push consul "$name"/usr/bin/
  done
  
  get_all_ips

  # create bootstrap config with ip address
  /bin/sed s/myaddress/"$bootstrap_ip"/g config/bootstrap.json > bootstrap_consul1.json
  # move in bootstrap config into container into bootstrap directory
  /usr/bin/lxc exec "${names[0]}" -- mkdir -p /consul/bootstrap
  /usr/bin/lxc file push bootstrap_consul1.json "${names[0]}"/consul/bootstrap/
  # move in bootstrap init script and make executable
  /usr/bin/lxc file push config/consul-bootstrap "${names[0]}"/etc/init.d/
  /usr/bin/lxc exec "${names[0]}" -- chmod 755 /etc/init.d/consul-bootstrap
  # launch bootstrap if consul not already bootstrapped
  if /usr/bin/lxc exec "${names[0]}" -- cat /consul/data/raft/peers.json > /dev/null 2>&1; then
    /usr/bin/lxc exec "${names[0]}" -- rc-service consul-bootstrap stop > /dev/null 2>&1
    /usr/bin/lxc exec "${names[0]}" -- rc-service consul-server start
  else
    /usr/bin/lxc exec "${names[0]}" -- rc-service consul-bootstrap start
  fi
  #create server config files
  /bin/sed s/ips/"$bootstrap_ip\", \"$consul3_ip"/g config/server.json > server_consul2.json
  /bin/sed s/ips/"$bootstrap_ip\", \"$consul2_ip"/g config/server.json > server_consul3.json
  /bin/sed s/ips/"$consul2_ip\", \"$consul3_ip"/g config/server.json > server_consul1.json
  
  # push server config files and init script to server nodes
  for name in "${names[@]}";
    do
    /usr/bin/lxc file push server_"$name".json $name/consul/server/
    /usr/bin/lxc file push config/consul-server $name/etc/init.d/
    /usr/bin/lxc exec $name -- chmod 755 /etc/init.d/consul-server
    /usr/bin/lxc exec $name -- rc-update add consul-server default
  done
  
  #start server nodes
  /usr/bin/lxc exec "${names[1]}" -- rc-service consul-server start
  /usr/bin/lxc exec "${names[2]}" -- rc-service consul-server start
  
  # cleanup
  /bin/rm bootstrap_consul1.json
  /bin/rm -f server_consul*
  /bin/rm consul

  # print ips of cluster
  output

}

case "$1" in
	create)
      create
      ;;
    destroy)
      destroy
      ;;
    start)
      start
      ;;
    stop)
      stop
      ;;
    restart)
      restart
      ;;
    *) 
      echo "Usage: $0 command {options:create,destroy,start,stop,restart}"
      exit 1
esac
