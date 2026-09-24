module Items
  # Applies a person's correction to one of an item's labels. The label becomes human-set, so later
  # classification must leave it alone, and the item no longer needs review.
  #
  #   Items::CorrectLabel.call(item:, label: "product", value: "3", actor: Current.user)  # => true
  #
  # Product and category take an id, or blank for none; sentiment takes a sentiment name; relevant takes
  # "true" or "false". Raises Invalid for an unknown label or value. Writes a `corrected` event only when
  # the value changes.
  class CorrectLabel
    class Invalid < ArgumentError; end

    LABELS = %w[product category sentiment relevant].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(item:, label:, value:, actor:)
      @item = item
      @label = label.to_s
      @value = value.to_s.strip
      @actor = actor
    end

    def call
      raise Invalid, "#{@label.inspect} is not a label" unless LABELS.include?(@label)

      from = current_value
      to = new_value
      @item.transaction do
        @item.update!(attribute => to, "#{@label}_human_set" => true, needs_review: false)
        @item.record_event!(:corrected, actor: @actor, label: @label, **change_data(from, to)) unless from == to
      end
      true
    end

    private

    def attribute
      { "product" => :product, "category" => :category }.fetch(@label, @label.to_sym)
    end

    def current_value
      @item.public_send(attribute)
    end

    def new_value
      case @label
      when "product" then option(Product)
      when "category" then option(Category)
      when "sentiment" then sentiment
      when "relevant" then relevant
      end
    end

    def option(model)
      return if @value.blank?

      record = model.find_by(id: @value)
      raise Invalid, "#{model.model_name.human} #{@value} does not exist" unless record
      raise Invalid, "#{record.name} is retired" if record.retired? && record != current_value

      record
    end

    def sentiment
      return if @value.blank?
      raise Invalid, "#{@value.inspect} is not a sentiment" unless Item.sentiments.key?(@value)

      @value
    end

    def relevant
      raise Invalid, "relevant must be true or false" unless %w[true false].include?(@value)

      @value == "true"
    end

    def change_data(from, to)
      return { from: from, to: to } unless from.is_a?(ApplicationRecord) || to.is_a?(ApplicationRecord)

      { from: from&.name, to: to&.name, from_id: from&.id, to_id: to&.id }
    end
  end
end
