require "test_helper"

class Webhooks::SignatureTest < ActiveSupport::TestCase
  SECRET = "hhsec_test_secret"
  BODY = '{"text":"The app keeps crashing"}'

  test "sign matches an independently computed HMAC-SHA256 of the timestamp and body" do
    time = Time.zone.at(1_790_000_000)
    expected = OpenSSL::HMAC.hexdigest("SHA256", SECRET, "1790000000.#{BODY}")

    assert_equal "t=1790000000,v1=#{expected}", Webhooks::Signature.sign(SECRET, BODY, time: time)
  end

  test "verify accepts a fresh signature" do
    assert Webhooks::Signature.verify(SECRET, BODY, Webhooks::Signature.sign(SECRET, BODY))
  end

  test "verify rejects a changed body, another secret, or a tampered digest" do
    header = Webhooks::Signature.sign(SECRET, BODY)

    assert_not Webhooks::Signature.verify(SECRET, "#{BODY} ", header)
    assert_not Webhooks::Signature.verify("other", BODY, header)
    assert_not Webhooks::Signature.verify(SECRET, BODY, header.sub(/v1=\h/, "v1=g"))
  end

  test "verify rejects signatures outside the tolerance window in either direction" do
    now = Time.current

    assert Webhooks::Signature.verify(SECRET, BODY, Webhooks::Signature.sign(SECRET, BODY, time: now - 300), now: now)
    assert_not Webhooks::Signature.verify(SECRET, BODY, Webhooks::Signature.sign(SECRET, BODY, time: now - 301), now: now)
    assert_not Webhooks::Signature.verify(SECRET, BODY, Webhooks::Signature.sign(SECRET, BODY, time: now + 301), now: now)
    assert Webhooks::Signature.verify(SECRET, BODY, Webhooks::Signature.sign(SECRET, BODY, time: now - 900),
      tolerance: 1_000, now: now)
  end

  test "verify accepts any v1 value so senders can rotate secrets" do
    header = Webhooks::Signature.sign(SECRET, BODY)
    both = "#{header},v1=#{Webhooks::Signature.sign("old", BODY).split("v1=").last}"

    assert Webhooks::Signature.verify(SECRET, BODY, both)
    assert Webhooks::Signature.verify("old", BODY, both)
  end

  test "verify rejects blank, malformed, or timestamp-less headers and a blank secret" do
    header = Webhooks::Signature.sign(SECRET, BODY)

    assert_not Webhooks::Signature.verify(SECRET, BODY, nil)
    assert_not Webhooks::Signature.verify(SECRET, BODY, "")
    assert_not Webhooks::Signature.verify(SECRET, BODY, "garbage")
    assert_not Webhooks::Signature.verify(SECRET, BODY, header.sub(/t=\d+,/, ""))
    assert_not Webhooks::Signature.verify(SECRET, BODY, header.sub(/t=\d+/, "t=soon"))
    assert_not Webhooks::Signature.verify("", BODY, header)
  end
end
