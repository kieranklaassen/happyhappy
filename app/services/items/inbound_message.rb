module Items
  # The one shape every connector normalizes a provider message into before
  # calling Items::Ingest. external_id is unique per source; thread_key groups
  # messages into one item per source kind (KTD2).
  class InboundMessage
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :external_id, :string
    attribute :thread_key, :string
    attribute :body, :string, default: ""
    attribute :occurred_at, :datetime
    attribute :author_handle, :string
    attribute :author_name, :string
    attribute :author_email, :string
    attribute :permalink, :string
    attribute :raw_payload, default: -> { {} }

    validates :external_id, :thread_key, :occurred_at, presence: true
    validate :raw_payload_is_a_hash

    def initialize(attributes = {})
      super
      self.occurred_at ||= Time.current
      self.body = body.to_s
    end

    private

    def raw_payload_is_a_hash
      errors.add(:raw_payload, "must be a hash") unless raw_payload.is_a?(Hash)
    end
  end
end
