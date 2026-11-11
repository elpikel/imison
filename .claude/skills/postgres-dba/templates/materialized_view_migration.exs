defmodule Shop.Repo.Migrations.CreateProductSalesSummaries do
  use Ecto.Migration

  def up do
    execute("""
    CREATE MATERIALIZED VIEW product_sales_summaries AS
    SELECT
      order_line.product_id,
      sum(order_line.quantity) AS units_sold,
      sum(order_line.quantity * order_line.unit_price) AS revenue
    FROM order_lines AS order_line
    JOIN orders AS ord ON ord.id = order_line.order_id
    WHERE ord.status IN ('paid', 'shipped')
    GROUP BY order_line.product_id
    """)

    # REFRESH ... CONCURRENTLY requires a unique index on the view.
    execute("""
    CREATE UNIQUE INDEX product_sales_summaries_unique_idx
    ON product_sales_summaries (product_id)
    """)
  end

  def down do
    execute("DROP MATERIALIZED VIEW IF EXISTS product_sales_summaries")
  end
end
