class Searcher < Object
  def initialize(search)
    @search_results = search
  end

  def search()
  end

  private

  def do_search(search_results)
    search_results.ordered.paginate(page: page, per_page: 25)
  end
end
