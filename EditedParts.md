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
  this->beforeSave(cname, value, options);
```

UPDATEASYNC

Added the following code

```

  this->beforeSave(cname, value, options);

```

REMOVEASYNC

Added the following:

```
  this->beforeRemove(cname, value, options);

  // END OF ADDITIONS

```

TRUNCATEASYNC

Added the following:

```

  this->beforeTruncate(collectionName, options);

  // END OF ADDITIONS

```

```

// Added by Gaitho
// Validate collections before inset and update
/// @brief return the collection
void transaction::Methods::beforeSave(std::string const& cname, VPackSlice value,
                                      OperationOptions const& options) {
  int collType = getCollectionType(cname);

  std::string qry =
      "LET colschema = SCHEMA_GET('" + cname + "') RETURN colschema";
  auto binds = std::make_shared<VPackBuilder>();
  binds->openObject();
  binds->close();

  arangodb::aql::Query query(_transactionContext, aql::QueryString(qry), binds);
  aql::QueryResult queryResult = query.executeSync();

  if (queryResult.result.fail()) {
    THROW_ARANGO_EXCEPTION(queryResult.result);
  }
  VPackBuilder linkCollections;
  linkCollections.openObject();

  if (queryResult.data->slice().length() == 1) {
    for (auto it : VPackArrayIterator(queryResult.data->slice())) {
      if (it.isObject()) {
        VPackSlice schemaItem = it.value();
        VPackSlice propertyvalue(
            schemaItem.get(std::vector<std::string>({"rule", "properties"})));

        if (propertyvalue.isObject()) {
          for (auto prop : VPackObjectIterator(propertyvalue)) {
            std::string fieldName = prop.key.copyString();
            VPackSlice modelProp = prop.value;
            VPackSlice links = modelProp.get("linkCollections");

            if (links.isArray()) {
              std::string linkStr = "";
              for (auto link : VPackArrayIterator(links)) {
                if (link.isString()) {
                  std::string cName = link.copyString();
                  linkStr = linkStr + cName + "/";
                }
              }
              linkCollections.add(fieldName, VPackValue(linkStr));
            }
          }
        }
      }
    }
  }
  linkCollections.close();

  auto getLinkCollections = [&]() { return linkCollections.slice(); };

  /*
   Method to check for document links
  */
  auto checkVertexField = [&](std::string const& fieldName, const auto docValue) {
    VPackSlice _idValue = docValue.get("_id");

    auto throwError = [&]() {
      THROW_ARANGO_EXCEPTION_MESSAGE(TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
                                     +" invalid _id value in : " + fieldName);
    };

    VPackSlice fColls = getLinkCollections();
    std::string collStr = "";

    if (fColls.isObject()) {
      VPackSlice colls = fColls.get(fieldName);
      if (colls.isString()) {
        collStr = colls.copyString();
      }
      // for (auto const& prop : VPackObjectIterator(fColls)) {
      //   if (prop.key.isString() && prop.value.isString()) {
      //     std::string key = prop.key.copyString();
      //     std::string val = prop.value.copyString();
      //     std::cout << key << " : " << val << std::endl;
      //     if (key == fieldName) {
      //     }
      //   }
      // }
    }

    if (_idValue.isNone() && docValue.length() >= 1 && collStr.size() >= 1) {
      THROW_ARANGO_EXCEPTION_MESSAGE(TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
                                     +"_id value not found in colection " +
                                         cname + ". Expected " + fieldName +
                                         " to have a key `_id`.");
    }

    if (!_idValue.isNone()) {
      if (!_idValue.isString()) {
        throwError();
      }
      std::string link_id = _idValue.copyString();

      if (link_id.find("/") == std::string::npos) {
        throwError();
      }

      std::string docCollectionName = link_id.substr(0, link_id.find("/"));
      std::string doc_key = link_id.substr(link_id.find("/") + 1, link_id.size());

      if (docCollectionName.size() == 0 || doc_key.size() == 0) {
        throwError();
      }

      if (collStr.size() == 0) {
        THROW_ARANGO_EXCEPTION_MESSAGE(
            TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
            "invalid schema for: " + cname +
                ". Could not find linkCollections definition for " +
                docCollectionName + " in property " + fieldName);
      }

      if (collStr.find(docCollectionName + "/") == std::string::npos) {
        THROW_ARANGO_EXCEPTION_MESSAGE(
            TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
            "invalid schema for: " + cname +
                ". Shema found but without a valid linkCollection for `" +
                docCollectionName + "` in property " + fieldName);
      } else {
        VPackBuilder checkDocument;
        {
          VPackObjectBuilder guard(&checkDocument);
          checkDocument.add(StaticStrings::KeyString, VPackValue(doc_key));
        }

        OperationOptions docOptions;
        OperationResult checkDoc =
            this->document(docCollectionName, checkDocument.slice(), docOptions);

        if (!checkDoc.ok()) {
          THROW_ARANGO_EXCEPTION_MESSAGE(TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
                                         link_id +
                                             " is not a valid document in " + fieldName +
                                             " property of collection " + cname);
        }
      }
    }
  };

  /*
   Method to validate edges before insert. It checks that both referenced documents in _from and _to actualy exists
  */
  auto checkValue = [&](const auto docValue) {
    std::string _from;
    std::string _to;

    for (auto it : VPackObjectIterator(docValue)) {
      std::string fieldName = it.key.copyString();

      if (fieldName == "_from" || fieldName == "_to") {
        std::string collref = fieldName.substr(0, fieldName.size() - 3);

        auto throwError = [&]() {
          THROW_ARANGO_EXCEPTION_MESSAGE(TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
                                         +" invalid value in : " + fieldName);
        };

        if (!it.value.isString()) {
          throwError();
        }

        std::string doc_id = it.value.copyString();

        if (doc_id.find("/") == std::string::npos) {
          throwError();
        }

        std::string docCollectionName = doc_id.substr(0, doc_id.find("/"));
        std::string doc_key = doc_id.substr(doc_id.find("/") + 1, doc_id.size());

        if (docCollectionName.size() == 0 || doc_key.size() == 0) {
          throwError();
        }

        if (fieldName == "_from") {
          _from = doc_id;
        } else {
          _to = doc_id;
        }

        VPackBuilder checkDocument;
        {
          VPackObjectBuilder guard(&checkDocument);
          checkDocument.add(StaticStrings::KeyString, VPackValue(doc_key));
        }

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

  if (value.isObject() && !options.isRestore) {
    for (auto it : VPackObjectIterator(value)) {
      std::string fieldName = it.key.copyString();

      VPackSlice fieldValue = it.value;

      if (fieldValue.isObject()) {
        checkVertexField(fieldName, fieldValue);
      }

      if (fieldValue.isArray()) {
        for (auto it2 : VPackArrayIterator(fieldValue)) {
          if (it2.isObject()) {
            checkVertexField(fieldName, it2.value());
          }
        }
      }
    }

    if (collType == 3) {
      checkValue(value);
    }
  }

  if (value.isArray() && !options.isRestore) {
    for (auto it : VPackArrayIterator(value)) {
      if (it.isObject()) {
        for (auto it : VPackObjectIterator(it.value())) {
          std::string fieldName = it.key.copyString();

          VPackSlice fieldValue = it.value;

          if (fieldValue.isObject()) {
            checkVertexField(fieldName, fieldValue);
          }

          if (fieldValue.isArray()) {
            for (auto it2 : VPackArrayIterator(fieldValue)) {
              if (it2.isObject()) {
                checkVertexField(fieldName, it2.value());
              }
            }
          }
        }

        if (collType == 3) {
          checkValue(it.value());
        }
      }
    }
  }
}

void transaction::Methods::beforeRemove(std::string const& cname, VPackSlice value,
                                        OperationOptions const& options) {
  auto getSchemaReferences = [&](std::string collName, std::string _key) {
    // QUERY the schema definition on this collection
    std::string qry =
        "LET colschema = SCHEMA_GET('" + collName + "') RETURN colschema";
    auto binds = std::make_shared<VPackBuilder>();
    binds->openObject();
    binds->close();

    arangodb::aql::Query query(_transactionContext, aql::QueryString(qry), binds);
    aql::QueryResult queryResult = query.executeSync();

    if (queryResult.result.fail()) {
      THROW_ARANGO_EXCEPTION(queryResult.result);
    }

    if (queryResult.result.ok()) {
      VPackSlice schemaArray = queryResult.data->slice();

      if (schemaArray.length() == 1) {
        for (auto it : VPackArrayIterator(schemaArray)) {
          if (it.isObject()) {
            VPackSlice schemaItem = it.value();
            VPackSlice propertyvalue(schemaItem.get(
                std::vector<std::string>({"rule", "properties"})));

            for (auto prop : VPackObjectIterator(propertyvalue)) {
              std::string fieldName = prop.key.copyString();
              VPackSlice modelProp = prop.value;
              VPackSlice linkCollections = modelProp.get("linkCollections");
              if (linkCollections.isArray()) {
                for (auto link : VPackArrayIterator(linkCollections)) {
                  if (link.isString()) {
                    std::string collectionName = link.copyString();

                    if (collectionName == cname) {
                      std::string link_id = collectionName + "/" + _key;

                      std::string q = "FOR r IN @@coll FILTER r." + fieldName +
                                      "._id =='" + link_id + "' || '" +
                                      link_id + "' IN r." + fieldName +
                                      "[*]._id LIMIT 1 RETURN r";

                      auto binds = std::make_shared<VPackBuilder>();
                      binds->openObject();
                      binds->add("@coll", VPackValue(collName));
                      binds->close();
                      arangodb::aql::Query query(_transactionContext,
                                                 aql::QueryString(q), binds);
                      aql::QueryResult queryResult = query.executeSync();

                      Result res = queryResult.result;
                      if (queryResult.result.ok()) {
                        VPackSlice array = queryResult.data->slice();
                        if (array.length() > 0) {
                          THROW_ARANGO_EXCEPTION_MESSAGE(
                              TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
                              "cannot remove document " + _key +
                                  " because it is referenced in " + collName +
                                  ", under the property " + fieldName);
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  };
  /*
    Validate whether any of the documents have been referenced in other edges
  */
  auto validateReference = [&](std::string collName, std::string _key) {
    std::string _id = cname + "/" + _key;
    std::string q = "FOR r IN @@coll FILTER r._from=='" + _id +
                    "' || r._to=='" + _id + "' LIMIT 1 RETURN r";

    auto binds = std::make_shared<VPackBuilder>();
    binds->openObject();
    binds->add("@coll", VPackValue(collName));
    binds->close();
    arangodb::aql::Query query(_transactionContext, aql::QueryString(q), binds);
    aql::QueryResult queryResult = query.executeSync();

    Result res = queryResult.result;
    if (queryResult.result.ok()) {
      VPackSlice array = queryResult.data->slice();
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
    // std::string _id = doc_id.toString();

    for (auto collection : vocbase().collections(false)) {
      int collType = collection->type();
      std::string collName = collection->name();
      if (collType == 3) {
        validateReference(collName, _key);
      } else {
        if (collName != cname) {
          getSchemaReferences(collName, _key);
        }
      }
    }
  }

  if (value.isArray()) {
    for (VPackSlice docValue : VPackArrayIterator(value)) {
      arangodb::velocypack::StringRef key(transaction::helpers::extractKeyPart(docValue));

      std::string _key = key.toString();

      for (auto collection : vocbase().collections(false)) {
        int collType = collection->type();
        std::string collName = collection->name();
        if (collType == 3) {
          validateReference(collName, _key);
        } else {
          if (collName != cname) {
            getSchemaReferences(collName, _key);
          }
        }
      }
    }
  }
}

void transaction::Methods::beforeTruncate(std::string const& cname,
                                          OperationOptions const& options) {
  auto getSchemaReferences = [&](std::string collName) {
    // QUERY the schema definition on this collection
    std::string qry =
        "LET colschema = SCHEMA_GET('" + collName + "') RETURN colschema";
    auto binds = std::make_shared<VPackBuilder>();
    binds->openObject();
    binds->close();

    arangodb::aql::Query query(_transactionContext, aql::QueryString(qry), binds);
    aql::QueryResult queryResult = query.executeSync();

    if (queryResult.result.fail()) {
      THROW_ARANGO_EXCEPTION(queryResult.result);
    }

    if (queryResult.result.ok()) {
      VPackSlice schemaArray = queryResult.data->slice();

      if (schemaArray.length() == 1) {
        for (auto it : VPackArrayIterator(schemaArray)) {
          if (it.isObject()) {
            VPackSlice schemaItem = it.value();
            VPackSlice propertyvalue(schemaItem.get(
                std::vector<std::string>({"rule", "properties"})));

            for (auto prop : VPackObjectIterator(propertyvalue)) {
              std::string fieldName = prop.key.copyString();
              VPackSlice modelProp = prop.value;
              VPackSlice linkCollections = modelProp.get("linkCollections");
              if (linkCollections.isArray()) {
                for (auto link : VPackArrayIterator(linkCollections)) {
                  if (link.isString()) {
                    std::string collectionName = link.copyString();

                    if (cname == collectionName) {
                      std::string link_id = collectionName + "/";

                      std::string q =
                          "FOR r IN @@coll FILTER r." + fieldName +
                          "._id LIKE '" + link_id + "%' || CONCAT(r." + fieldName +
                          "[*]._id) LIKE '" + link_id + "%' LIMIT 1 RETURN r";

                      auto binds = std::make_shared<VPackBuilder>();
                      binds->openObject();
                      binds->add("@coll", VPackValue(collName));
                      binds->close();
                      arangodb::aql::Query query(_transactionContext,
                                                 aql::QueryString(q), binds);
                      aql::QueryResult queryResult = query.executeSync();

                      Result res = queryResult.result;

                      if (queryResult.result.ok()) {
                        VPackSlice array = queryResult.data->slice();
                        if (array.length() > 0) {
                          THROW_ARANGO_EXCEPTION_MESSAGE(
                              TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
                              "cannot truncate collection " + collectionName +
                                  " because documents have references in " +
                                  collName + ", under field name " + fieldName);
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  };

  /*
   Validate whether any of the documents have been referenced in other edges
 */

  auto validateReference = [&](std::string collName) {
    std::string q = "FOR r IN @@coll FILTER r._from LIKE '" + cname +
                    "/%' || r._to LIKE '" + cname + "/%' LIMIT 1 RETURN r";

    auto binds = std::make_shared<VPackBuilder>();
    binds->openObject();
    binds->add("@coll", VPackValue(collName));
    binds->close();
    arangodb::aql::Query query(_transactionContext, aql::QueryString(q), binds);
    aql::QueryResult queryResult = query.executeSync();

    Result res = queryResult.result;
    if (queryResult.result.ok()) {
      VPackSlice array = queryResult.data->slice();

      if (array.length() > 0) {
        THROW_ARANGO_EXCEPTION_MESSAGE(TRI_ERROR_ARANGO_DOCUMENT_TYPE_INVALID,
                                       "cannot truncate collection because "
                                       "documents have references in " +
                                           collName);
      }
    }
  };

  for (auto collection : vocbase().collections(false)) {
    int collType = collection->type();
    std::string collName = collection->name();

    if (collName != cname) {
      getSchemaReferences(collName);
    }
    if (collType == 3) {
      validateReference(collName);
    }
  }
}

```
