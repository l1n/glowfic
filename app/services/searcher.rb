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
end
