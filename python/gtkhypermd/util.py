class cached_property(object):
    def __init__(self, func):
        self.func = func

    def __get__(self, obj, type=None):
        if obj is None:
            return self
        else:
            val = obj.__dict__[self.func.__name__] = self.func(obj)
            return val
