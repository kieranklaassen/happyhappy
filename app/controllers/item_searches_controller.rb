# Smart search on Enter (U25): starts a run over the current feed search and
# returns to the feed with its run id, where the smart prop streams in.
class ItemSearchesController < InertiaController
  def create
    query = ItemsQuery.from_params(params)
    run = FeedSearch.smart(params[:q], user: Current.user, filters: query.filters, suppressed: Array(params[:removed]))

    redirect_to items_path(search_params.merge(run_id: run&.id).compact_blank)
  rescue ItemsQuery::InvalidFilter
    redirect_to items_path(q: params[:q])
  end

  private

  def search_params
    params.permit(:q, *ItemsQuery::SCALAR_FILTERS, *ItemsQuery::LIST_FILTERS, removed: [],
      **ItemsQuery::LIST_FILTERS.index_with { [] }).to_h
  end
end
