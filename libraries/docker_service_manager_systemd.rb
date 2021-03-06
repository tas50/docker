module DockerCookbook
  class DockerServiceManagerSystemd < DockerServiceBase
    use_automatic_resource_name

    provides :docker_service_manager, platform: 'fedora'

    provides :docker_service_manager, platform: %w(redhat centos scientific) do |node| # ~FC005
      node['platform_version'].to_f >= 7.0
    end

    provides :docker_service_manager, platform: 'debian' do |node|
      node['platform_version'].to_f >= 8.0
    end

    provides :docker_service_manager, platform: 'ubuntu' do |node|
      node['platform_version'].to_f >= 15.04
    end

    action :start do
      # Needed for Debian / Ubuntu
      directory '/usr/libexec' do
        owner 'root'
        group 'root'
        mode '0755'
        action :create
      end

      # this script is called by the main systemd unit file, and
      # spins around until the service is actually up and running.
      template '/usr/libexec/docker-wait-ready' do
        path '/usr/libexec/docker-wait-ready'
        source 'systemd/docker-wait-ready.erb'
        owner 'root'
        group 'root'
        mode '0755'
        variables(docker_cmd: docker_cmd)
        cookbook 'docker'
        action :create
      end

      # this is the main systemd unit file
      template '/lib/systemd/system/docker.service' do
        path '/lib/systemd/system/docker.service'
        source 'systemd/docker.service.erb'
        owner 'root'
        group 'root'
        mode '0644'
        variables(
          config: new_resource,
          docker_daemon_cmd: docker_daemon_cmd
        )
        cookbook 'docker'
        notifies :run, 'execute[systemctl daemon-reload]', :immediately
        notifies :restart, new_resource unless ::File.exist? '/etc/docker-firstconverge'
        notifies :restart, new_resource if auto_restart
        action :create
      end

      file '/etc/docker-firstconverge' do
        action :create
      end

      # avoid 'Unit file changed on disk' warning
      execute 'systemctl daemon-reload' do
        command '/bin/systemctl daemon-reload'
        action :nothing
      end

      # tmpfiles.d config so the service survives reboot
      template '/usr/lib/tmpfiles.d/docker.conf' do
        path '/usr/lib/tmpfiles.d/docker.conf'
        source 'systemd/tmpfiles.d.conf.erb'
        owner 'root'
        group 'root'
        mode '0644'
        variables(config: new_resource)
        cookbook 'docker'
        action :create
      end

      # service management resource
      service 'docker' do
        provider Chef::Provider::Service::Systemd
        supports status: true
        action [:enable, :start]
        only_if { ::File.exist?('/lib/systemd/system/docker.service') }
      end
    end

    action :stop do
      # service management resource
      service 'docker' do
        provider Chef::Provider::Service::Systemd
        supports status: true
        action [:disable, :stop]
        only_if { ::File.exist?('/lib/systemd/system/docker.service') }
      end
    end

    action :restart do
      action_stop
      action_start
    end
  end
end
