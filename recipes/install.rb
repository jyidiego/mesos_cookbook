#
# Cookbook Name:: mesos
# Recipe:: install
#
# Copyright (C) 2015 Medidata Solutions, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe 'chef-sugar'

include_recipe 'apt' if debian?

include_recipe 'java::default'

distro = node['platform']
distro_version = node['platform_version']
mesos_version = node['mesos']['version']

# First check if we have metadata for configured version
unless node['mesos']['mesosphere_packages'].key?(mesos_version)
  Chef::Application.fatal!("There is no metadata defined for your configured Mesos version: #{mesos_version}", 1000)
end

# Next check if we support this distro
unless node['mesos']['mesosphere_packages'][mesos_version].key?(distro)
  Chef::Application.fatal!("There is no metadata defined for your OS: #{distro}", 1001)
end

# Finally check if we support this particular distro version
unless node['mesos']['mesosphere_packages'][mesos_version][distro].key?(distro_version)
  Chef::Application.fatal!("There is no metadata defined for your OS version: #{distro_version}", 1002)
end

package_url = node['mesos']['mesosphere_packages'][mesos_version][distro][distro_version]['package_url']
package_checksum = node['mesos']['mesosphere_packages'][mesos_version][distro][distro_version]['checksum']

directory '/etc/mesos-chef'

case distro
when 'debian', 'ubuntu'
  %w( unzip default-jre-headless libcurl3 libsvn1).each do |pkg|
    package pkg do
      action :install
    end
  end

  remote_file "#{Chef::Config[:file_cache_path]}/mesos.deb" do
    source package_url
    checksum package_checksum
    action :create
    not_if { ::File.exist? '/usr/local/sbin/mesos-master' }
  end

  dpkg_package 'mesos' do
    source "#{Chef::Config[:file_cache_path]}/mesos.deb"
    not_if { ::File.exist? '/usr/local/sbin/mesos-master' }
  end
when 'rhel', 'centos', 'amazon', 'scientific'
  %w( unzip libcurl ).each do |pkg|
    yum_package pkg do
      action :install
    end
  end

  yum_package 'jdk' do
    action :purge
  end

  execute 'update java alternatives' do
    command '/usr/sbin/alternatives --auto java'
    action :run
  end

  execute 'ldconfig' do
    command '/sbin/ldconfig'
    action :nothing
  end

  file '/etc/ld.so.conf.d/jre.conf' do
    content "#{node['java']['java_home']}/jre/lib/amd64/server"
    notifies :run, 'execute[ldconfig]', :immediately
    mode 0644
  end

  remote_file "#{Chef::Config[:file_cache_path]}/mesos-#{node['mesos']['version']}.rpm" do
    source package_url
    checksum package_checksum
    action :create
    not_if { ::File.exist? '/usr/local/sbin/mesos-master' }
  end

  rpm_package 'mesos' do
    source "#{Chef::Config[:file_cache_path]}/mesos-#{node['mesos']['version']}.rpm"
    not_if { ::File.exist? '/usr/local/sbin/mesos-master' }
  end
end

# Set init to 'stop' by default for mesos master.
# Running mesos::master recipe will reset this to 'start'
template '/etc/init/mesos-master.conf' do
  source 'mesos-master.conf.erb'
  variables(
    action: 'stop'
  )
end

# Set init to 'stop' by default for mesos slave.
# Running mesos::slave recipe will reset this to 'start'
template '/etc/init/mesos-slave.conf' do
  source 'mesos-slave.conf.erb'
  variables(
    action: 'stop'
  )
end

if distro == 'debian'
  bash 'reload-configuration-debian' do
    user 'root'
    code <<-EOH
    update-rc.d -f mesos-master remove
    EOH
    not_if { ::File.exist? '/usr/local/sbin/mesos-master' }
  end
else
  bash 'reload-configuration' do
    user 'root'
    code <<-EOH
    initctl reload-configuration
    EOH
    not_if { ::File.exist? '/usr/local/sbin/mesos-master' }
  end
end
