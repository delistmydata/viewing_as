ViewingAs.configure do |c|
  c.timeout = 30.minutes
  c.may_impersonate = ->(user) { user.admin? }
  c.may_be_viewed = lambda do |target, _admin|
    if target.admin? then "That account is an administrator."
    elsif !target.reviewable? then "That customer has withdrawn permission for review."
    else true
    end
  end
end
