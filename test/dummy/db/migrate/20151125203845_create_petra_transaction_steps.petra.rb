# This migration comes from petra (originally 20151124124445)
class CreatePetraTransactionSteps < ActiveRecord::Migration
  def change
    create_table :petra_transaction_steps do |t|
      t.belongs_to :petra_transaction
      t.timestamps null: false
    end
  end
end
