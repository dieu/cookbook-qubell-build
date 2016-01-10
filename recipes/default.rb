# Recipe cookbook-qubell-build  app  from git , parse war files and copy to cookbook-qubell-build target
#
case node['platform_family']
  when "debian"
    execute "update packages cache" do
      command "apt-get update"
    end
  end

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
    mvn_version = node['cookbook-qubell-build']['maven_version']
    remote_file "/opt/apache-maven.tar.gz" do
      source "http://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/#{mvn_version}/apache-maven-#{mvn_version}-bin.tar.gz"
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

directory node['cookbook-qubell-build']['target'] do
  action :create
end

directory "/tmp/checksum/" do
   action :create
end

md5_file = "/tmp/checksum/mvn_dir.md5"

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
  command "cd #{node['cookbook-qubell-build']['dest_path']}/webapp; for i in $(find -regex '.*/target/[^/]*.war');do cp $i #{node['cookbook-qubell-build']['target']};done"
  notifies :create, "ruby_block[set attrs]"
  action :nothing
end

bash "create md5" do
  code <<-EEND
    md5sum -b #{node['cookbook-qubell-build']['target']}/*.war > #{md5_file}
  EEND
  not_if "md5sum -c #{md5_file}"
end

ruby_block "set attrs" do
   block do
      dir = node['cookbook-qubell-build']['target']
      artifacts = (Dir.entries(dir).select {|f| !File.directory? f}).map {|f| "file://" + File.join(dir, f)}
      artifacts = artifacts.sort
      node.set['cookbook-qubell-build']['artifacts'] = artifacts
   end
end

