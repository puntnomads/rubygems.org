module RuboCop::Cop
  class Style::CustomSafeNavigationCop < Cop
    MSG = "Use ruby safe navigation opetator (&.) instead of try".freeze

    def_node_matcher :try_call?, <<-PATTERN
      (send (...) :try (...))
    PATTERN

    def_node_matcher :try_bang_call?, <<-PATTERN
      (send (...) :try! (...))
    PATTERN

  end
end
