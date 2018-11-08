class Searcher < Object
  extend ActiveModel::Translation
  extend ActiveModel::Validations

  def initialize(search)
    @search_results = search
    @errors = ActiveModel::Errors.new(self)
  end

  attr_accessor :name
  attr_reader   :errors
  
  def search()
  end

  private

  def do_search(search_results, page)
    search_results.ordered.paginate(page: page, per_page: 25)
  end
end
