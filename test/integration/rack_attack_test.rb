require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.clear

    @ip_address = "1.2.3.4"
    @user = create(:user, email: "nick@example.com", password: PasswordHelpers::SECURE_TEST_PASSWORD)
  end

  def exceeding_limit
    (Rack::Attack::REQUEST_LIMIT * 1.25).to_i
  end

  def exceeding_email_limit
    (Rack::Attack::REQUEST_LIMIT_PER_EMAIL * 1.25).to_i
  end

  def exceeding_exp_base_limit
    (Rack::Attack::EXP_BASE_REQUEST_LIMIT * 1.25).to_i
  end

  def under_limit
    (Rack::Attack::REQUEST_LIMIT * 0.5).to_i
  end

  def under_email_limit
    (Rack::Attack::REQUEST_LIMIT_PER_EMAIL * 0.5).to_i
  end

  def limit_period
    Rack::Attack::LIMIT_PERIOD
  end

  def push_limit_period
    Rack::Attack::PUSH_LIMIT_PERIOD
  end

  def exp_base_limit_period
    Rack::Attack::EXP_BASE_LIMIT_PERIOD
  end

  def exceed_limit_for(scope)
    update_limit_for("#{scope}:#{@ip_address}", exceeding_limit)
  end

  def exceed_email_limit_for(scope)
    update_limit_for("#{scope}:#{@user.email}", exceeding_email_limit)
  end

  def exceed_push_limit_for(scope)
    exceeding_push_limit = (Rack::Attack::PUSH_LIMIT * 1.25).to_i
    update_limit_for("#{scope}:#{@ip_address}", exceeding_push_limit, push_limit_period)
  end

  def exceed_exp_base_limit_for(scope)
    update_limit_for("#{scope}:#{@ip_address}", exceeding_exp_base_limit, exp_base_limit_period)
  end

  def stay_under_limit_for(scope)
    update_limit_for("#{scope}:#{@ip_address}", under_limit)
  end

  def stay_under_email_limit_for(scope)
    update_limit_for("#{scope}:#{@user.email}", under_email_limit)
  end

  def stay_under_push_limit_for(scope)
    under_push_limit = (Rack::Attack::PUSH_LIMIT * 0.5).to_i
    update_limit_for("#{scope}:#{@user.email}", under_push_limit)
  end

  def stay_under_exp_base_limit_for(scope)
    under_exp_base_limit = (Rack::Attack::EXP_BASE_REQUEST_LIMIT * 0.5).to_i
    update_limit_for("#{scope}:#{@user.email}", under_exp_base_limit, exp_base_limit_period)
  end

  def update_limit_for(key, limit, period = limit_period)
    limit.times { Rack::Attack.cache.count(key, period) }
  end

  def exceed_exponential_limit_for(scope, level)
    expo_exceeding_limit = exceeding_exp_base_limit * level
    expo_limit_period = exp_base_limit_period**level
    expo_exceeding_limit.times { Rack::Attack.cache.count("#{scope}:#{@ip_address}", expo_limit_period) }
  end


  def expected_retry_after(level)
    now = Time.now.to_i
    period = Rack::Attack::EXP_BASE_LIMIT_PERIOD**level
    (period - (now % period)).to_s
  end

  context "requests is lower than limit" do
    should "allow sign in" do
      stay_under_limit_for("clearance/ip/1")

      post "/session",
        params: { session: { who: @user.email, password: @user.password } },
        headers: { REMOTE_ADDR: @ip_address }
      follow_redirect!

      assert_response :success
    end

    should "allow sign up" do
      stay_under_limit_for("clearance/ip/1")

      user = build(:user)
      post "/users",
        params: { user: { email: user.email, password: user.password } },
        headers: { REMOTE_ADDR: @ip_address }
      follow_redirect!

      assert_response :success
    end

    should "allow forgot password" do
      stay_under_limit_for("clearance/ip/1")
      stay_under_email_limit_for("password/email")

      post "/passwords",
        params: { password: { email: @user.email } },
        headers: { REMOTE_ADDR: @ip_address }

      assert_response :success
    end

    should "allow api_key show" do
      stay_under_limit_for("api_key/ip")

      get "/api/v1/api_key.json",
        env: { "HTTP_AUTHORIZATION" => encode(@user.handle, @user.password) },
        headers: { REMOTE_ADDR: @ip_address }

      assert_response :success
    end

    should "allow email confirmation resend" do
      stay_under_limit_for("clearance/ip/1")
      stay_under_email_limit_for("email_confirmations/email")

      post "/email_confirmations",
        params: { email_confirmation: { email: @user.email } },
        headers: { REMOTE_ADDR: @ip_address }
      follow_redirect!
      assert_response :success
    end

    context "api requests" do
      setup do
        @rubygem = create(:rubygem, name: "test", number: "0.0.1")
        @rubygem.ownerships.create(user: @user)
      end

      should "allow gem yank by ip" do
        stay_under_exp_base_limit_for("api/ip/1")

        delete "/api/v1/gems/yank",
          params: { gem_name: @rubygem.to_param, version: @rubygem.latest_version.number },
          headers: { REMOTE_ADDR: @ip_address, HTTP_AUTHORIZATION: @user.api_key }

        assert_response :success
      end

      should "allow gem push by ip" do
        stay_under_push_limit_for("api/push/ip")

        post "/api/v1/gems",
          params: gem_file("test-1.0.0.gem").read,
          headers: { REMOTE_ADDR: @ip_address, HTTP_AUTHORIZATION: @user.api_key, CONTENT_TYPE: "application/octet-stream" }

        assert_response :success
      end

      should "allow owner add by ip" do
        second_user = create(:user)
        stay_under_exp_base_limit_for("api/ip/1")

        post "/api/v1/gems/#{@rubygem.name}/owners",
          params: { rubygem_id: @rubygem.to_param, email: second_user.email },
          headers: { REMOTE_ADDR: @ip_address, HTTP_AUTHORIZATION: @user.api_key }

        assert_response :success
      end

      should "allow owner remove by ip" do
        second_user = create(:user)
        @rubygem.ownerships.create(user: second_user)
        stay_under_exp_base_limit_for("api/ip/1")

        delete "/api/v1/gems/#{@rubygem.name}/owners",
          params: { rubygem_id: @rubygem.to_param, email: second_user.email },
          headers: { REMOTE_ADDR: @ip_address, HTTP_AUTHORIZATION: @user.api_key }

        assert_response :success
      end
    end

    context "params" do
      should "return 400 for bad request" do
        post "/session"

        assert_response :bad_request
      end

      should "return 401 for unauthorized request" do
        post "/session", params: { session: { password: @user.password } }

        assert_response :unauthorized
      end
    end

    context "expontential backoff" do
      context "with successful gem push" do
        setup do
          Rack::Attack::EXP_BACKOFF_LEVELS.each do |level|
            under_backoff_limit = (Rack::Attack::EXP_BASE_REQUEST_LIMIT * level) - 1
            @push_exp_throttle_level_key = "#{Rack::Attack::PUSH_EXP_THROTTLE_KEY}/#{level}:#{@ip_address}"
            under_backoff_limit.times { Rack::Attack.cache.count(@push_exp_throttle_level_key, exp_base_limit_period**level) }
          end

          post "/api/v1/gems",
            params: gem_file("test-0.0.0.gem").read,
            headers: { REMOTE_ADDR: @ip_address, HTTP_AUTHORIZATION: @user.api_key, CONTENT_TYPE: "application/octet-stream" }
        end

        should "reset gem push rate limit rack attack key" do
          Rack::Attack::EXP_BACKOFF_LEVELS.each do |level|
            period = exp_base_limit_period**level

            time_counter = (Time.now.to_i / period).to_i
            prev_time_counter = time_counter - 1

            assert_nil Rack::Attack.cache.read("#{time_counter}:#{@push_exp_throttle_level_key}")
            assert_nil Rack::Attack.cache.read("#{prev_time_counter}:#{@push_exp_throttle_level_key}")
          end
        end

        should "not rate limit successive requests" do
          post "/api/v1/gems",
            params: gem_file("test-1.0.0.gem").read,
            headers: { REMOTE_ADDR: @ip_address, HTTP_AUTHORIZATION: @user.api_key, CONTENT_TYPE: "application/octet-stream" }

          assert_response :ok
        end
      end
    end
  end

  context "requests is higher than limit" do
    should "throttle sign in" do
      exceed_exp_base_limit_for("clearance/ip/1")

      post "/session",
        params: { session: { who: @user.email, password: @user.password } },
        headers: { REMOTE_ADDR: @ip_address }

      assert_response :too_many_requests
    end

    should "throttle mfa sign in" do
      exceed_exp_base_limit_for("clearance/ip/1")
      @user.enable_mfa!(ROTP::Base32.random_base32, :ui_only)

      post "/session/mfa_create",
        params: { otp: ROTP::TOTP.new(@user.mfa_seed).now },
        headers: { REMOTE_ADDR: @ip_address }

      assert_response :too_many_requests
    end

    should "throttle sign up" do
      exceed_exp_base_limit_for("clearance/ip/1")

      user = build(:user)
      post "/users",
        params: { user: { email: user.email, password: user.password } },
        headers: { REMOTE_ADDR: @ip_address }

      assert_response :too_many_requests
    end

    should "throttle forgot password" do
      exceed_exp_base_limit_for("clearance/ip/1")

      post "/passwords",
        params: { password: { email: @user.email } },
        headers: { REMOTE_ADDR: @ip_address }

      assert_response :too_many_requests
    end

    should "throttle mfa forgot password" do
      exceed_exp_base_limit_for("clearance/ip/1")

      @user.forgot_password!
      @user.enable_mfa!(ROTP::Base32.random_base32, :ui_only)

      post "/users/#{@user.id}/password/mfa_edit",
        params: { user_id: @user.id, token: @user.confirmation_token, otp: ROTP::TOTP.new(@user.mfa_seed).now },
        headers: { REMOTE_ADDR: @ip_address }

      assert_response :too_many_requests
    end

    should "throttle api_key show" do
      exceed_limit_for("api_key/ip")

      get "/api/v1/api_key.json",
        env: { "HTTP_AUTHORIZATION" => encode(@user.handle, @user.password) },
        headers: { REMOTE_ADDR: @ip_address }

      assert_response :too_many_requests
    end

    should "throttle profile update" do
      cookies[:remember_token] = @user.remember_token

      exceed_exp_base_limit_for("clearance/ip/1")
      patch "/profile",
        headers: { REMOTE_ADDR: @ip_address }

      assert_response :too_many_requests
    end

    should "throttle profile delete" do
      cookies[:remember_token] = @user.remember_token

      exceed_exp_base_limit_for("clearance/ip/1")
      delete "/profile",
        headers: { REMOTE_ADDR: @ip_address }

      assert_response :too_many_requests
    end

    context "email confirmation" do
      should "throttle by ip" do
        exceed_exp_base_limit_for("clearance/ip/1")

        post "/email_confirmations",
          params: { email_confirmation: { email: @user.email } },
          headers: { REMOTE_ADDR: @ip_address }
        assert_response :too_many_requests
      end

      should "throttle by email" do
        exceed_email_limit_for("email_confirmations/email")

        post "/email_confirmations", params: { email_confirmation: { email: @user.email } }
        assert_response :too_many_requests
      end
    end

    context "password update" do
      should "throttle by ip" do
        exceed_exp_base_limit_for("clearance/ip/1")

        post "/passwords",
          params: { password: { email: @user.email } },
          headers: { REMOTE_ADDR: @ip_address }

        assert_response :too_many_requests
      end

      should "throttle by email" do
        exceed_email_limit_for("password/email")

        post "/passwords", params: { password: { email: @user.email } }
        assert_response :too_many_requests
      end
    end

    context "api requests" do
      setup do
        @rubygem = create(:rubygem, name: "test", number: "0.0.1")
        @rubygem.ownerships.create(user: @user)
      end

      should "throttle gem yank by ip" do
        exceed_exp_base_limit_for("api/ip/1")

        delete "/api/v1/gems/yank",
          params: { gem_name: @rubygem.to_param, version: @rubygem.latest_version.number },
          headers: { REMOTE_ADDR: @ip_address, HTTP_AUTHORIZATION: @user.api_key }

        assert_response :too_many_requests
      end

      should "throttle gem push by ip" do
        exceed_push_limit_for("api/push/ip")

        post "/api/v1/gems",
          params: gem_file("test-1.0.0.gem").read,
          headers: { REMOTE_ADDR: @ip_address, HTTP_AUTHORIZATION: @user.api_key, CONTENT_TYPE: "application/octet-stream" }

        assert_response :too_many_requests
      end

      should "throttle owner add by ip" do
        second_user = create(:user)
        exceed_exp_base_limit_for("api/ip/1")

        post "/api/v1/gems/#{@rubygem.name}/owners",
          params: { rubygem_id: @rubygem.to_param, email: second_user.email },
          headers: { REMOTE_ADDR: @ip_address, HTTP_AUTHORIZATION: @user.api_key }

        assert_response :too_many_requests
      end

      should "throttle owner remove by ip" do
        second_user = create(:user)
        @rubygem.ownerships.create(user: second_user)
        exceed_exp_base_limit_for("api/ip/1")

        delete "/api/v1/gems/#{@rubygem.name}/owners",
          params: { rubygem_id: @rubygem.to_param, email: second_user.email },
          headers: { REMOTE_ADDR: @ip_address, HTTP_AUTHORIZATION: @user.api_key }

        assert_response :too_many_requests
      end
    end

    context "exponential backoff" do
      Rack::Attack::EXP_BACKOFF_LEVELS.each do |level|
        should "throttle for mfa sign in at level #{level}" do
          freeze_time do
            exceed_exponential_limit_for("clearance/ip/#{level}", level)

            post "/users",
              params: { user: { email: @user.email, password: @user.password } },
              headers: { REMOTE_ADDR: @ip_address }

            assert_response :too_many_requests
            assert_equal expected_retry_after(level), @response.headers["Retry-After"]
          end
        end

        should "throttle gem push at level #{level}" do
          freeze_time do
            exceed_exponential_limit_for("#{Rack::Attack::PUSH_EXP_THROTTLE_KEY}/#{level}", level)

            post "/api/v1/gems",
              params: gem_file("test-0.0.0.gem").read,
              headers: { REMOTE_ADDR: @ip_address, HTTP_AUTHORIZATION: @user.api_key, CONTENT_TYPE: "application/octet-stream" }

            assert_response :too_many_requests
            assert_equal expected_retry_after(level), @response.headers["Retry-After"]
          end
        end
      end
    end

    context "with per email limits" do
      setup { update_limit_for("password/email:#{@user.email}", exceeding_limit) }

      should "throttle for sign in ignoring case" do
        post "/passwords",
          params: { password: { email: "Nick@example.com" } }

        assert_response :too_many_requests
      end

      should "throttle for sign in ignoring spaces" do
        post "/passwords",
          params: { password: { email: "n ick@example.com" } }

        assert_response :too_many_requests
      end
    end
  end
end
