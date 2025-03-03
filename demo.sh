#!/bin/bash

# Step 1: Create the NLP model and model group
curl -XPUT "http://localhost:9200/_cluster/settings?pretty" -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "plugins.ml_commons.only_run_on_ml_node": "false",
    "plugins.ml_commons.model_access_control_enabled": "true",
    "plugins.ml_commons.native_memory_threshold": "99"
  }
}
'
curl -XPOST "http://localhost:9200/_plugins/_ml/model_groups/_register?pretty" -H 'Content-Type: application/json' -d'
{
  "name": "local_model_group",
  "description": "A model group for local models"
}
'

## The response will include the model group ID for example:
# {
#   "model_group_id": "Z1eQf4oB5Vm0Tdw8EIP2"
#   "status": "CREATED"
# }

# Register the locally provided model and use the model group ID from the previous step
curl -XPOST "http://localhost:9200/_plugins/_ml/models/_register?pretty" -H 'Content-Type: application/json' -d'
{
  "name": "huggingface/sentence-transformers/msmarco-distilbert-base-tas-b",
  "version": "1.0.2",
  "model_group_id": "ZyYlTpUBshYgm7pIiTSs",
  "model_format": "TORCH_SCRIPT"
}
'

## The response will include the task_id for example:
# {
#   "task_id": "aVeif4oB5Vm0Tdw8zYO2"
#   "status": "CREATED"
# }

# Check the status of the task to see if the model is ready and model id
curl -XGET "http://localhost:9200/_plugins/_ml/tasks/cVeMb4kBJ1eYAeTMFFgj?pretty"


# Deploy the model
curl -XPOST "http://localhost:9200/_plugins/_ml/models/aSYmTpUBshYgm7pILzRl/_deploy?pretty"

# Test the model
curl -XPOST "http://localhost:9200/_plugins/_ml/_predict/text_embedding/aSYmTpUBshYgm7pILzRl" -H 'Content-Type: application/json' -d'
{
  "text_docs":[ "today is sunny"],
  "return_number": true,
  "target_response": ["sentence_embedding"]
}
'

# Step 2: Create the NLP ingest pipeline
curl -XPUT "http://localhost:9200/_ingest/pipeline/nlp-ingest-pipeline?pretty" -H 'Content-Type: application/json' -d'
{
  "description": "An NLP ingest pipeline",
  "processors": [
    {
      "text_embedding": {
        "model_id": "aSYmTpUBshYgm7pILzRl",
        "field_map": {
          "text": "passage_embedding"
        }
      }
    }
  ]
}
'

# Step 3: Create the index with the NLP ingest pipeline

# Lucene KNN engine
curl -XPUT "http://localhost:9200/my-nlp-index?pretty" -H 'Content-Type: application/json' -d'
{
  "settings": {
    "index.knn": true,
    "default_pipeline": "nlp-ingest-pipeline"
  },
  "mappings": {
    "properties": {
      "id": {
        "type": "text"
      },
      "passage_embedding": {
        "type": "knn_vector",
        "dimension": 768,
        "method": {
          "engine": "lucene",
          "space_type": "l2",
          "name": "hnsw",
          "parameters": {}
        }
      },
      "text": {
        "type": "text"
      }
    }
  }
}
'

# jVector KNN engine
curl -XPUT "http://localhost:9200/my-nlp-index?pretty" -H 'Content-Type: application/json' -d'
{
  "settings": {
    "index.knn": true,
    "default_pipeline": "nlp-ingest-pipeline"
  },
  "mappings": {
    "properties": {
      "id": {
        "type": "text"
      },
      "passage_embedding": {
        "type": "knn_vector",
        "dimension": 768,
        "method": {
          "engine": "jvector",
          "space_type": "l2",
          "name": "disk_ann",
          "parameters": {}
        }
      },
      "text": {
        "type": "text"
      }
    }
  }
}
'

# Step 4: Ingest documents into the index
curl -XPUT "http://localhost:9200/my-nlp-index/_doc/1?pretty" -H 'Content-Type: application/json' -d'
{
  "text": "A West Virginia university womens basketball team , officials , and a small gathering of fans are in a West Virginia arena .",
  "id": "4319130149.jpg"
}
'
curl -XPUT "http://localhost:9200/my-nlp-index/_doc/2?pretty" -H 'Content-Type: application/json' -d'
{
  "text": "A wild animal races across an uncut field with a minimal amount of trees .",
  "id": "1775029934.jpg"
}
'
curl -XPUT "http://localhost:9200/my-nlp-index/_doc/3?pretty" -H 'Content-Type: application/json' -d'
{
  "text": "People line the stands which advertise Freemonts orthopedics , a cowboy rides a light brown bucking bronco .",
  "id": "2664027527.jpg"
}
'
curl -XPUT "http://localhost:9200/my-nlp-index/_doc/4?pretty" -H 'Content-Type: application/json' -d'
{
  "text": "A man who is riding a wild horse in the rodeo is very near to falling off .",
  "id": "4427058951.jpg"
}
'
curl -XPUT "http://localhost:9200/my-nlp-index/_doc/5?pretty" -H 'Content-Type: application/json' -d'
{
  "text": "A rodeo cowboy , wearing a cowboy hat , is being thrown off of a wild white horse .",
  "id": "2691147709.jpg"
}
'

# When the documents are ingested we should see the embeddings
curl -XGET "http://localhost:9200/my-nlp-index/_doc/1?pretty"

# Step 5: Search the data

# Search using neural index
curl -XGET "http://localhost:9200/my-nlp-index/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "_source": {
    "excludes": [
      "passage_embedding"
    ]
  },
  "query": {
    "neural": {
      "passage_embedding": {
        "query_text": "wild west",
        "model_id": "aSYmTpUBshYgm7pILzRl",
        "k": 5
      }
    }
  }
}
'

# Configure pipeline for hybrid search
curl -XPUT "http://localhost:9200/_search/pipeline/nlp-search-pipeline?pretty" -H 'Content-Type: application/json' -d'
{
  "description": "Post processor for hybrid search",
  "phase_results_processors": [
    {
      "normalization-processor": {
        "normalization": {
          "technique": "min_max"
        },
        "combination": {
          "technique": "arithmetic_mean",
          "parameters": {
            "weights": [
              0.3,
              0.7
            ]
          }
        }
      }
    }
  ]
}
'

# Search using hybrid index
curl -XGET "http://localhost:9200/my-nlp-index/_search?pretty&search_pipeline=nlp-search-pipeline" -H 'Content-Type: application/json' -d'
{
  "_source": {
    "exclude": [
      "passage_embedding"
    ]
  },
  "query": {
    "hybrid": {
      "queries": [
        {
          "match": {
            "text": {
              "query": "cowboy rodeo bronco"
            }
          }
        },
        {
          "neural": {
            "passage_embedding": {
              "query_text": "wild west",
              "model_id": "aSYmTpUBshYgm7pILzRl",
              "k": 2
            }
          }
        }
      ]
    }
  }
}
'

# Step 6: Cleanup
# Delete the index
curl -XDELETE "http://localhost:9200/my-nlp-index?pretty"
# Delete the search pipeline
curl -XDELETE "http://localhost:9200/_search/pipeline/nlp-search-pipeline?pretty"
# Delete the ingest pipeline
curl -XDELETE "http://localhost:9200/_ingest/pipeline/nlp-ingest-pipeline?pretty"
# Delete the model
curl -XPOST "http://localhost:9200/_plugins/_ml/models/aVeif4oB5Vm0Tdw8zYO2/_undeploy"
curl -XDELETE "http://localhost:9200/_plugins/_ml/models/aVeif4oB5Vm0Tdw8zYO2"
curl -XDELETE "http://localhost:9200/_plugins/_ml/model_groups/Z1eQf4oB5Vm0Tdw8EIP2"
