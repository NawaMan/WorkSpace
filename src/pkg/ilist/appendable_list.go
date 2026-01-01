package ilist

type AppendableList[TYPE any] struct {
	elements []TYPE
}

// NewAppendableList creates a new empty AppendableList.
func NewAppendableList[TYPE any]() *AppendableList[TYPE] {
	return &AppendableList[TYPE]{elements: nil}
}

// NewAppendableListFrom creates a new AppendableList with the given initial elements.
func NewAppendableListFrom[TYPE any](elements ...TYPE) *AppendableList[TYPE] {
	if len(elements) == 0 {
		return &AppendableList[TYPE]{elements: nil}
	}
	copied := make([]TYPE, len(elements))
	copy(copied, elements)
	return &AppendableList[TYPE]{elements: copied}
}

// Append adds one or more elements to the end of the list.
func (thisBuilder *AppendableList[TYPE]) Append(values ...TYPE) {
	thisBuilder.elements = append(thisBuilder.elements, values...)
}

// ExtendBySlice appends all elements from the given slice.
func (thisBuilder *AppendableList[TYPE]) ExtendBySlice(slice []TYPE) {
	if len(slice) == 0 {
		return
	}
	copied := make([]TYPE, len(slice))
	copy(copied, slice)
	thisBuilder.elements = append(thisBuilder.elements, copied...)
}

// ExtendByList appends all elements from the given List.
func (thisBuilder *AppendableList[TYPE]) ExtendByList(list List[TYPE]) {
	if list.Length() == 0 {
		return
	}
	copied := make([]TYPE, len(list.elements))
	copy(copied, list.elements)
	thisBuilder.elements = append(thisBuilder.elements, copied...)
}

// Length returns the number of elements in the list.
func (thisBuilder *AppendableList[TYPE]) Length() int {
	return len(thisBuilder.elements)
}

// Slice returns a copy of the current elements as a slice.
func (thisBuilder *AppendableList[TYPE]) Slice() []TYPE {
	if len(thisBuilder.elements) == 0 {
		return nil
	}
	copied := make([]TYPE, len(thisBuilder.elements))
	copy(copied, thisBuilder.elements)
	return copied
}

// Snapshot creates an immutable List with a copy of the current elements.
func (thisBuilder *AppendableList[TYPE]) Snapshot() List[TYPE] {
	if len(thisBuilder.elements) == 0 {
		return List[TYPE]{elements: nil}
	}
	copied := make([]TYPE, len(thisBuilder.elements))
	copy(copied, thisBuilder.elements)
	return List[TYPE]{elements: copied}
}

// Clone creates a copy of this AppendableList.
func (thisBuilder *AppendableList[TYPE]) Clone() *AppendableList[TYPE] {
	if len(thisBuilder.elements) == 0 {
		return &AppendableList[TYPE]{elements: nil}
	}
	copied := make([]TYPE, len(thisBuilder.elements))
	copy(copied, thisBuilder.elements)
	return &AppendableList[TYPE]{elements: copied}
}
