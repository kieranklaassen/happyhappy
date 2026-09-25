module FeedSearch
  # The SQLite FTS5 index behind keystroke search: one document per item
  # (rowid = items.id) with the item's author fields and every message body.
  # Item and Message refresh it after commit; `bin/rails search:reindex`
  # rebuilds it.
  #
  #   FeedSearch::TextIndex.matching(Item.all, %w[charged twice])  # => items whose text has both words
  module TextIndex
    TABLE = "item_search_documents".freeze

    module_function

    # Every token must appear in the author or body; each token also matches
    # as a prefix, so a half-typed word already finds its items.
    def matching(scope, tokens)
      expression = match_expression(tokens)
      return if expression.nil?

      scope.where("#{scope.quoted_table_name}.id IN (SELECT rowid FROM #{TABLE} WHERE #{TABLE} MATCH ?)", expression)
    end

    def match_expression(tokens)
      terms = Array(tokens).filter_map do |token|
        text = token.to_s.gsub(/[^\p{Alnum}@.'\- ]/, " ").squish
        %("#{text.gsub('"', '""')}"*) if text.present?
      end
      terms.join(" ").presence
    end

    def refresh(item_ids)
      ids = Array(item_ids).compact.uniq
      return if ids.empty?

      connection = Item.connection
      Item.transaction do
        connection.exec_delete(Item.sanitize_sql_array([ "DELETE FROM #{TABLE} WHERE rowid IN (?)", ids.map { |id| Integer(id) } ]))
        documents(ids).each do |document|
          connection.exec_insert(Item.sanitize_sql_array([ "INSERT INTO #{TABLE} (rowid, author, body) VALUES (?, ?, ?)", *document ]))
        end
      end
    end

    def rebuild
      Item.in_batches(of: 500) { |batch| refresh(batch.ids) }
    end

    def documents(ids)
      bodies = Message.where(item_id: ids).order(:occurred_at, :id).pluck(:item_id, :body)
        .group_by(&:first).transform_values { |rows| rows.map(&:last).join("\n") }
      Item.where(id: ids).pluck(:id, :author_handle, :author_name, :author_email).map do |id, *authors|
        [ id, authors.compact_blank.join(" "), bodies.fetch(id, "") ]
      end
    end
  end
end
