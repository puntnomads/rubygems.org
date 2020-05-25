require "unpwn"

class UnpwnValidator < ActiveModel::EachValidator

  private

  def unpwn
    @unpwn ||= Unpwn.new(min: nil, max: nil, request_options: { read_timeout: 3 })
  end
end
