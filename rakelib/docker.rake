# frozen_string_literal: true

require "yaml"
require_relative "./../gem/lib/rb_sys/version"

DOCKERFILES = Dir["docker/Dockerfile.*"]
DOCKERFILE_PLATFORMS = DOCKERFILES.map { |f| File.extname(f).delete(".") }
DOCKERFILE_PLATFORM_PAIRS = DOCKERFILES.zip(DOCKERFILE_PLATFORMS)
DOCKER = ENV.fetch("RBSYS_DOCKER", "docker")

def run_gh_workflow(file_name)
  begin
    require "json"
    require "yaml"

    workflow = YAML.safe_load(File.read(file_name))

    sh "gh workflow run \"#{workflow["name"]}\" && sleep 3"
    id = JSON.parse(`gh run list --workflow=#{File.basename(file_name)} --limit=1 --json="databaseId"`).first["databaseId"]
    system "gh run watch #{id}"
    sh "osascript -e 'display notification \"#{workflow["name"]} workflow finished (#{id})\" with title \"GitHub Workflow\"'"
  rescue Interrupt
    sh "gh run cancel #{id}"
  end
end

desc "Build the docker images on github"
task ".github/workflows/docker.yml" do |t, _args|
  run_gh_workflow t.name
end

desc "Run CI workflow"
task ".github/workflows/ci.yml" do |t, _args|
  run_gh_workflow t.name
end

namespace :docker do
  # New images based on cross-rs
  cross_tasks = Dir["docker/cross/*/Dockerfile"].map do |dockerfile|
    platform = File.basename(File.dirname(dockerfile))

    namespace :cross do
      image = "rbsys/cross-#{platform}:#{RbSys::VERSION}"

      namespace :build do
        desc "Build the #{image.inspect} docker image (based on cross-rs)"
        task platform do
          sh "#{DOCKER} build #{ENV["RBSYS_DOCKER_BUILD_EXTRA_ARGS"]} -t #{image} -f #{dockerfile} --progress=plain ./docker/cross"
        end
      end

      namespace :push do
        desc "Push the #{image.inspect} docker image (based on cross-rs)"
        task platform => "docker:cross:build:#{platform}" do
          sh "docker push #{image}"
        end
      end
    end

    platform
  end

  desc "Build the cross docker images (based on cross-rs)"
  task "cross:build" => cross_tasks.map { |t| "cross:build:#{t}" }

  desc "Push the cross docker images (based on cross-rs)"
  task "cross:push" => cross_tasks.map { |t| "cross:push:#{t}" }

  DOCKERFILE_PLATFORM_PAIRS.each do |pair|
    dockerfile, arch = pair

    namespace :build do
      desc "Build docker image for %s" % arch
      task arch do
        sh "#{DOCKER} build #{ENV["RBSYS_DOCKER_BUILD_EXTRA_ARGS"]} -f #{dockerfile} --tag rbsys/rcd:#{arch} --tag rbsys/rake-compiler-dock-mri-#{arch}:#{RbSys::VERSION} --tag rbsys/#{arch}:#{RbSys::VERSION} ./docker"
      end
    end

    namespace :sh do
      desc "Shell into docker image for %s" % arch
      task arch do
        system "docker run --rm --privileged --entrypoint /bin/bash -it rbsys/rcd:#{arch}"
      end
    end
  end

  desc "Build docker images for all platforms"
  task build: DOCKERFILE_PLATFORMS.map { |p| "build:#{p}" }

  DOCKERFILE_PLATFORMS.each do |arch|
    desc "Push #{arch} docker image"
    task "push:#{arch}" => "build:#{arch}" do
      sh "docker push rbsys/rake-compiler-dock-mri-#{arch}:#{RbSys::VERSION}"
      sh "docker push rbsys/rcd:#{arch}"
      sh "docker push rbsys/#{arch}:#{RbSys::VERSION}"
    end
  end

  desc "Push docker images for all platforms"
  task push: DOCKERFILE_PLATFORMS.map { |p| "push:#{p}" }
end
