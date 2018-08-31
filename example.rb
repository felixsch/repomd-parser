#!/usr/bin/env ruby

require 'bundler/setup'
require 'uri'
require 'repomd_parser'
require 'tmpdir'
require 'fileutils'
require 'net/http'
require 'uri'

def fetch(url, limit = 10)
  raise RuntimeError, 'Too many redirects' if limit == 0

  url = url.class == String ? URI.parse(url) : url
  req = Net::HTTP::Get.new(url, { 'User-Agent' => "repomd-parser/#{RepomdParser::VERSION}" })

  response = Net::HTTP.start(url.host, url.port, :use_ssl => url.instance_of?(URI::HTTPS)) do |http|
    http.request(req)
  end

  case response
    when Net::HTTPSuccess     then response
    when Net::HTTPRedirection then fetch(response['location'], limit - 1)
    else
      response.error!
  end
end

def make_url(repo_url, path)
  repo_url = URI.parse(repo_url)
  uri = URI.join(repo_url, path)
  uri.query = repo_url.query
  uri
end

def print_repo_stats(repo_url)
  repo_url += '/' unless repo_url =~ /\/^/

  tmpdir = Dir.mktmpdir
  repomd_file = File.join(tmpdir, 'repomd.xml')

  response = fetch(make_url(repo_url, 'repodata/repomd.xml'))

  File.open(repomd_file, 'wb') do |file|
    file.write(response.body)
  end

  stats = Hash.new { |hash, key| hash[key] = { count: 0, total_size: 0 } }
  metadata_files = Hash.new { |hash, key| hash[key] = [] }

  RepomdParser::RepomdXmlParser.new(repomd_file).parse.each do |xml_file|
    metadata_files[xml_file.type] << xml_file if %i[primary deltainfo].include?(xml_file.type)
  end

  metadata_files[:primary].each do |xml_file|
    filename = File.join(tmpdir, File.basename(xml_file.location))

    response = fetch(make_url(repo_url, xml_file.location))
    File.open(filename, 'wb') do |file|
      file.write(response.body)
    end

    rpms = RepomdParser::PrimaryXmlParser.new(filename, true).parse
    rpms.each do |package|
      stats[package[:arch]][:count] += 1
      stats[package[:arch]][:total_size] += package[:package_size]
    end
  end

  pretty_url = URI.parse(repo_url)
  pretty_url.query = nil

  puts
  puts "Statistics for #{pretty_url.to_s}"
  puts
  stats.each { |arch, data| printf "%08s: %06s packages, %6.02f gigabytes\n", arch, data[:count], data[:total_size].to_f / 1024 ** 3 }
ensure
  FileUtils.rm_r(tmpdir)
end

print_repo_stats('https://download.opensuse.org/update/leap/42.3/oss/')
print_repo_stats('http://download.fedoraproject.org/pub/fedora/linux/releases/28/Everything/x86_64/os/')
