# ArangoDB Customizaiton

We attemped to edit c++ code in ArangoDB becuase we had a need to make ArangoDB referential integrity with guarantee. Cloud Hub uses ArangoDB in most of the applications and we really love ArangoDB 🥑🥑. But the lack of referential integrity while inserting edges or removing documents that are connected was not cool. Whether using Graphs or Not, I think these guarantees should be guaranteed.

The Following c++ Files were edited. Of course we are aware that performance might be affected, but its a price we are aware of and are ready to pay until we see further improvements.

## Version

Current Edited version is 3.8.0

## Edit Files

/arangod/utils/SingleCollectionTransaction.h
remove the following

```
  DataSourceId addCollectionAtRuntime(std::string const& name,
                                      AccessMode::Type type) override final;
```

/arangod/utils/SingleCollectionTransaction.cpp

Remove the mothod

```
DataSourceId SingleCollectionTransaction::addCollectionAtRuntime(std::string const& name,
                                                                 AccessMode::Type type) {
  TRI_ASSERT(!name.empty());
  if ((name[0] < '0' || name[0] > '9') &&
      name != resolveTrxCollection()->collectionName()) {
    THROW_ARANGO_EXCEPTION_MESSAGE(TRI_ERROR_TRANSACTION_UNREGISTERED_COLLECTION,
                                   std::string(TRI_errno_string(TRI_ERROR_TRANSACTION_UNREGISTERED_COLLECTION)) + ": " + name);
  }

  if (AccessMode::isWriteOrExclusive(type) &&
      !AccessMode::isWriteOrExclusive(_accessType)) {
    // trying to write access a collection that is marked read-access
    THROW_ARANGO_EXCEPTION_MESSAGE(TRI_ERROR_TRANSACTION_UNREGISTERED_COLLECTION,
                                   std::string(TRI_errno_string(TRI_ERROR_TRANSACTION_UNREGISTERED_COLLECTION)) + ": " + name +
                                   " [" + AccessMode::typeString(type) + "]");
  }

  return _cid;
}

```

## Methods

arangod/Transaction/Methods.cpp
The following methods have been edited.

INSERTASYNC

```

/// @brief create one or multiple documents in a collection
/// the single-document variant of this operation will either succeed or,
/// if it fails, clean up after itself
Future<OperationResult> transaction::Methods::insertAsync(std::string const& cname,
                                                          VPackSlice value,
                                                          OperationOptions const& options) {
  TRI_ASSERT(_state->status() == transaction::Status::RUNNING);


  // std::string refError;

  if (!value.isObject() && !value.isArray()) {
    // must provide a document object or an array of documents
    events::CreateDocument(vocbase().name(), cname, value, options,
                           TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID);
    THROW_ARANGO_EXCEPTION(TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID);
  }

  // Method to validate edges before insert
  auto checkValue = [&](const auto docValue) {
    std::string _from;
    std::string _to;

    for (auto it : VPackObjectIterator(docValue)) {
      if (it.key.copyString() == "_from" || it.key.copyString() == "_to") {
        std::string doc_id = it.value.copyString();
        std::string docCollectionName = doc_id.substr(0, doc_id.find("/"));
        std::string doc_key = doc_id.substr(doc_id.find("/") + 1, doc_id.size());

        if (it.key.copyString() == "_from") {
          _from = doc_id;
        } else {
          _to = doc_id;
        }

        VPackBuilder checkDocument;
        {
          VPackObjectBuilder guard(&checkDocument);
          checkDocument.add(StaticStrings::KeyString, VPackValue(doc_key));
        }
        // bool hasRefError = false;

        OperationOptions docOptions;
        OperationResult checkDoc =
            this->document(docCollectionName, checkDocument.slice(), docOptions);

        if (!checkDoc.ok()) {
          THROW_ARANGO_EXCEPTION_MESSAGE(TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
                                         doc_id +
                                             " is not a valid document in : " + cname);
        }
      }
    }

    if (_from.size() > 0 && _from == _to) {
      THROW_ARANGO_EXCEPTION_MESSAGE(TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
                                     _from + " reference to same document " +
                                         _to + " in edge " + cname);
    }
  };

  if (value.isObject()) {
    checkValue(value);
  }

  if (value.isArray()) {
    for (auto it : VPackArrayIterator(value)) {
      if (it.isObject()) {
        checkValue(it.value());
      }
    }
  }

  if (value.isArray() && value.length() == 0) {
    events::CreateDocument(vocbase().name(), cname, value, options, TRI_ERROR_NO_ERROR);
    return emptyResult(options);
  }

  auto f = Future<OperationResult>::makeEmpty();
  if (_state->isCoordinator()) {
    f = insertCoordinator(cname, value, options);
  } else {
    OperationOptions optionsCopy = options;
    f = insertLocal(cname, value, optionsCopy);
  }

  return addTracking(std::move(f), [=](OperationResult&& opRes) {
    events::CreateDocument(vocbase().name(), cname,
                           (opRes.ok() && opRes.options.returnNew) ? opRes.slice() : value,
                           opRes.options, opRes.errorNumber());
    return std::move(opRes);
  });
}

```

UPDATEASYNC

Added the following code

```
/*
  Method to validate edges before insert. It checks that both referenced documents in _from and _to actualy exists
 */
  auto checkValue = [&](const auto docValue) {
    std::string _from;
    std::string _to;

    for (auto it : VPackObjectIterator(docValue)) {
      if (it.key.copyString() == "_from" || it.key.copyString() == "_to") {
        std::string doc_id = it.value.copyString();
        std::string docCollectionName = doc_id.substr(0, doc_id.find("/"));
        std::string doc_key = doc_id.substr(doc_id.find("/") + 1, doc_id.size());

        if (it.key.copyString() == "_from") {
          _from = doc_id;
        } else {
          _to = doc_id;
        }

        VPackBuilder checkDocument;
        {
          VPackObjectBuilder guard(&checkDocument);
          checkDocument.add(StaticStrings::KeyString, VPackValue(doc_key));
        }
        // bool hasRefError = false;

        OperationOptions docOptions;
        OperationResult checkDoc =
            this->document(docCollectionName, checkDocument.slice(), docOptions);

        if (!checkDoc.ok()) {
          THROW_ARANGO_EXCEPTION_MESSAGE(TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
                                         doc_id +
                                             " is not a valid document in : " + cname);
        }
      }
    }

    if (_to.size() > 0) {
      if (_from.size() == 0) {
        THROW_ARANGO_EXCEPTION_MESSAGE(
            TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
            " `_from` value is not supplied in edge " + cname);
      }
      if (_from == _to) {
        THROW_ARANGO_EXCEPTION_MESSAGE(TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
                                       _from + " reference to same document " +
                                           _to + " in edge " + cname);
      }
    }

    if (_from.size() > 0) {
      if (_to.size() == 0) {
        THROW_ARANGO_EXCEPTION_MESSAGE(TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
                                       " `_to` value is not supplied in edge " + cname);
      }
      if (_from == _to) {
        THROW_ARANGO_EXCEPTION_MESSAGE(TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
                                       _from + " reference to same document " +
                                           _to + " in edge " + cname);
      }
    }
  };

  if (newValue.isObject()) {
    checkValue(newValue);
  }

  if (newValue.isArray()) {
    for (auto it : VPackArrayIterator(newValue)) {
      if (it.isObject()) {
        checkValue(it.value());
      }
    }
  }

  // END ADDITIONS

```

REMOVEASYNC

Added the following:

```
/*
    Validate whether any of the documents have been referenced in other edges
  */
  auto validateReference = [&](std::string collName, std::string _key) {
    std::string _id = cname + "/" + _key;
    std::string q = "FOR r IN @@coll FILTER r._from=='" + _id +
                    "' || r._to=='" + _id + "'  LIMIT 1 RETURN r";
    auto binds = std::make_shared<VPackBuilder>();
    binds->openObject();
    binds->add("@coll", VPackValue(collName));
    binds->close();
    arangodb::aql::Query query(_transactionContext, aql::QueryString(q), binds);
    aql::QueryResult queryResult = query.executeSync();

    Result res = queryResult.result;
    if (queryResult.result.ok()) {
      VPackSlice array = queryResult.data->slice();
      std::cout << std::endl;
      std::cout << q << std::endl;
      std::cout << "RESULTS LENGTH " << array.length() << std::endl;
      std::cout << std::endl;

      if (array.length() > 0) {
        THROW_ARANGO_EXCEPTION_MESSAGE(TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
                                       "cannot remove document " + _key +
                                           " because it is referenced in " + collName);
      }
    }
  };

  if (value.isObject() || value.isString()) {
    arangodb::velocypack::StringRef key(transaction::helpers::extractKeyPart(value));
    std::string _key = key.toString();
    for (auto collection : vocbase().collections(false)) {
      int collType = collection->type();
      std::string collName = collection->name();

      std::cout << "COLL TYPE: " << collType << " COLL NAME: " << collName << std::endl;

      if (collType == 3) {
        validateReference(collName, _key);
      }
    }
  }

  if (value.isArray()) {
    for (VPackSlice docValue : VPackArrayIterator(value)) {
      arangodb::velocypack::StringRef key(transaction::helpers::extractKeyPart(docValue));
      std::string _key = key.toString();
      for (auto collection : vocbase().collections(false)) {
        std::string collName = collection->name();
        if (collection->type() == 3) {
          validateReference(collection->name(), _key);
        }
      }
    }
  }

  // END OF ADDITIONS

```
