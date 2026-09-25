# Full-text index for feed search (U25): one row per item, rowid = items.id,
# holding the item's author fields and every message body. Kept in sync by
# FeedSearch::TextIndex.
class CreateItemSearchDocuments < ActiveRecord::Migration[8.1]
  def up
    create_virtual_table :item_search_documents, :fts5, [ "author", "body", "tokenize='porter unicode61 remove_diacritics 2'" ]

    execute <<~SQL
      INSERT INTO item_search_documents (rowid, author, body)
      SELECT items.id,
        TRIM(COALESCE(items.author_handle, '') || ' ' || COALESCE(items.author_name, '') || ' ' || COALESCE(items.author_email, '')),
        COALESCE((SELECT GROUP_CONCAT(messages.body, char(10)) FROM messages WHERE messages.item_id = items.id), '')
      FROM items
    SQL
  end

  def down
    drop_table :item_search_documents
  end
end
