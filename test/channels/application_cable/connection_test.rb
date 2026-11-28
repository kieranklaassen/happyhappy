require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects with a valid signed session_id cookie" do
    session = users(:every_ana).sessions.create!
    cookies.signed[:session_id] = session.id

    connect

    assert_equal users(:every_ana), connection.current_user
  end

  test "rejects unauthorized connection without a session_id cookie" do
    assert_reject_connection { connect }
  end

  test "rejects unauthorized connection with an unknown session_id cookie" do
    cookies.signed[:session_id] = -1

    assert_reject_connection { connect }
  end

  test "rejects unauthorized connection with an expired session_id cookie" do
    session = users(:every_ana).sessions.create!
    expired_id = session.id
    session.destroy!
    cookies.signed[:session_id] = expired_id

    assert_reject_connection { connect }
  end
end
