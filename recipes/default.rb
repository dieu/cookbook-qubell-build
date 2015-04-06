# Recipe cookbook-qubell-build  app  from git , parse war files and copy to cookbook-qubell-build target
#
case node[:platform_family]
  when "debian"
    execute "update packages cache" do
      command "apt-get update"
    end

    service "ufw" do
      action :stop
    end
  when "rhel"
    service "iptables" do
      action :stop
    end
  end
case node['platform_family']
  when "debian"
    execute "update packages cache" do
      command "apt-get update"
    end
  end

include_recipe "python"
include_recipe "java"
include_recipe "git"
case node['platform_family']
  when "debian"
    include_recipe "apt"
    apt_repository "apache-maven3" do
      uri "http://ppa.launchpad.net/natecarlson/maven3/ubuntu/"
      distribution node['lsb']['codename']
      components   ['main']
      keyserver    'keyserver.ubuntu.com'
      key "3DD9F856"
    end
    package "maven3" do
      action :install
    end
    link "/usr/sbin/mvn" do
      to "/usr/bin/mvn3"
    end
  when "rhel"
    mvn_version = "3.2.1"
    remote_file "/opt/apache-maven.tar.gz" do
      source "http://mirror.olnevhost.net/pub/apache/maven/binaries/apache-maven-#{mvn_version}-bin.tar.gz"
    end

    bash "unpack apache-maven" do
      code <<-EEND
        tar -zxf /opt/apache-maven.tar.gz -C /opt/ && chmod 755 /opt/apache-maven-#{mvn_version}/bin/mvn
      EEND
    end

    link "/usr/sbin/mvn" do
      to "/opt/apache-maven-#{mvn_version}/bin/mvn"
    end
  end
service "SimpleHttpServer" do
 supports :restart => true
 action :nothing
end
template "/etc/init.d/SimpleHttpServer" do
  mode "0755"
  source "SimpleHttpServer-init.erb"
  variables(
    :port => node['cookbook-qubell-build']['port'],
    :host => node['cookbook-qubell-build']['host'],
    :target_dir => node['cookbook-qubell-build']['target']
    )
end

 directory node['cookbook-qubell-build']['target'] do
   action :create
 end

git "#{node['cookbook-qubell-build']['dest_path']}/webapp" do
  repository node['scm']['repository']
  revision node['scm']['revision']
  action :sync
  notifies :run, "execute[package]", :immediately
end
execute "package" do
  command "cd #{node['cookbook-qubell-build']['dest_path']}/webapp; mvn clean package -Dmaven.test.skip=true" 
  retries 3
  action :nothing
  notifies :run, "execute[copy_wars]", :immediately
end
execute "copy_wars" do
  command "rm -rf #{node['cookbook-qubell-build']['target']}/*;cd #{node['cookbook-qubell-build']['dest_path']}/webapp; for i in $(find -regex '.*/target/[^/]*.war');do cp $i #{node['cookbook-qubell-build']['target']}/`basename $i`-`md5sum $i| awk '{ print $1 }'`; done"
  notifies :create, "ruby_block[set attrs]"
  notifies :restart, "service[SimpleHttpServer]"
  action :nothing
end

ruby_block "set attrs" do
  block do
    dir = node['cookbook-qubell-build']['target']
    artifacts = (Dir.entries(dir).select {|f| !File.directory? f}).map {|f| "file://" + File.join(dir, f)}
    artifacts_urls = (Dir.entries(dir).select {|f| !File.directory? f}).map {|f| "http://" + "#{node['cookbook-qubell-build']['host']}:" + "#{node['cookbook-qubell-build']['port']}" + File.join("/", f)}
    artifacts_urls = artifacts_urls.sort
    artifacts = artifacts.sort
    node.set['cookbook-qubell-build']['artifacts'] = artifacts
    node.set['cookbook-qubell-build']['artifacts_urls'] = artifacts_urls
   end
end
