module Petra
  module PersistenceAdapters
    class FileAdapter < Adapter
      def persist!
        return true if queue.empty?

        # We currently only allow entries for one transaction in the queue
        with_transaction_lock(queue.first.transaction_identifier) do
          while (entry = queue.shift) do
            Petra.log "Would persist entry: #{entry.to_h.inspect}", :red
            create_entry_file(entry)
            entry.mark_as_persisted!
          end
        end
      end

      def transaction_identifiers
        # Wait until no other transaction is doing stuff that might lead to inconsistent data
        with_global_lock do
          ensure_directory_existence('transactions')
          storage_file_name('transactions').children.select(&:directory?).map(&:basename).map(&:to_s)
        end
      end

      def savepoints(transaction)
        with_transaction_lock(transaction.identifier) do
          return [] unless File.exists? storage_file_name('transactions', transaction.identifier)
          storage_file_name('transactions', transaction.identifier).children.select(&:directory?).map do |f|
            YAML.load_file(f.join('information.yml').to_s)[:savepoint]
          end
        end
      end

      def log_entries(section)
        with_transaction_lock(section.transaction.identifier) do
          section_dir = storage_file_name(*section_dirname(section))

          # If the given section has never been persisted before, we don't have to
          # search further for log entries
          return [] unless section_dir.exist?

          section_dir.children.select { |f| f.extname == '.entry' }.map do |f|
            entry_hash = YAML.load_file(f.to_s)
            Petra::Components::LogEntry.from_hash(section, entry_hash)
          end
        end
      end

      private

      def add_section_directory(section)
        dir = section_dirname(section)
        ensure_directory_existence(*dir)

        # If there is already a section directory/information file, we are done.
        return if storage_file_name(*dir, 'information.yml').exist?

        section_hash = {transaction_identifier: section.transaction.identifier,
                        savepoint:              section.savepoint,
                        savepoint_version:      section.savepoint_version}
        with_storage_file(*dir, 'information.yml', mode: 'w') do |f|
          YAML.dump(section_hash, f)
        end
      end

      def create_entry_file(entry)
        add_section_directory(entry.section)
        t = Time.now
        filename = "#{t.to_i}.#{t.nsec}.entry"
        with_storage_file(*section_dirname(entry.section), filename, mode: 'w') do |f|
          YAML.dump(entry.to_h, f)
        end
      end

      def section_dirname(section)
        ['transactions', section.transaction.identifier, section.savepoint_version.to_s]
      end
    end
  end
end