# Recorded Intercom notification payloads under test/fixtures/files/intercom/.
#
#   intercom_created                                  # conversation.user.created as recorded
#   intercom_replied(part_id: "p-2", body: "<p>Hi</p>") # newest part rewritten
module IntercomPayloads
  def intercom_payload(name)
    JSON.parse(file_fixture("intercom/#{name}.json").read)
  end

  def intercom_created
    intercom_payload("conversation_user_created")
  end

  def intercom_replied(**part_overrides)
    intercom_payload("conversation_user_replied").tap do |payload|
      part = payload.dig("data", "item", "conversation_parts", "conversation_parts").last
      author_type = part_overrides.delete(:author_type)
      part["author"]["type"] = author_type if author_type
      part.merge!(part_overrides.stringify_keys)
    end
  end
end
