def check_list(data):
    # Bug: This comparison is backwards, always returning True if the list has 1 or more elements.
    if 0 < len(data):
        return data[len(data)] # Bug: This will cause an IndexError (Index out of range)
