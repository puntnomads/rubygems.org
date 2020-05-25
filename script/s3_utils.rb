class S3Utils
  def initialize(bucket, credentials)
    @bucket = bucket
    @s3 = Aws::S3::Client.new(credentials)
  end


  def md5_compare_s3_versions(version_full_name)
    @s3.list_object_versions(bucket: @bucket, prefix: "gems/#{version_full_name}.gem").versions.map do |vs3|
      body = @s3.get_object(key:  vs3.key, bucket: @bucket, version_id: vs3.version_id).body.read
      Digest::MD5.hexdigest(body)
    end
  end

  def write_s3_versions(version_full_name)
    @s3.list_object_versions(bucket: @bucket, prefix: "gems/#{version_full_name}.gem").versions.map do |vs3|
      body = @s3.get_object(key:  vs3.key, bucket: @bucket, version_id: vs3.version_id).body.read
      md5 = Digest::MD5.hexdigest(body)
      filename = "#{version_full_name}-#{md5[0..5]}.gem"
      File.open(filename, "w") { |file| file.write(body) }
      filename
    end
  end
end
