#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <hiredis/hiredis.h>

// Structure to store node information
typedef struct {
    int node_id;
    int color;
    int *neighbors;
    int neighbor_count;
} NodeInfo;

// Extract node ID from key (e.g., "node_123" -> 123)
int get_node_id(const char *key) {
    const char *underscore = strchr(key, '_');
    if (!underscore) return -1;
    return atoi(underscore + 1);
}

// Get node color from Redis
int get_node_color(redisContext *context, const char *node_id) {
    char key[256];
    snprintf(key, sizeof(key), "node_%s_color", node_id);
    redisReply *reply = redisCommand(context, "GET %s", key);
    if (reply == NULL || reply->type == REDIS_REPLY_NIL) {
        if (reply) freeReplyObject(reply);
        return -1; // Not found
    }
    int color = atoi(reply->str);
    freeReplyObject(reply);
    return color;
}

// Get node status from Redis
int get_node_status(redisContext *context, const char *node_id) {
    char key[256];
    snprintf(key, sizeof(key), "node_%s_status", node_id);
    redisReply *reply = redisCommand(context, "GET %s", key);
    if (reply == NULL || reply->type == REDIS_REPLY_NIL) {
        if (reply) freeReplyObject(reply);
        return 0; // Not found = uncolored
    }
    int status = atoi(reply->str);
    freeReplyObject(reply);
    return status;
}

// Get all neighbors of a node
int* get_all_neighbours(redisContext *context, const char *node_id, int *neighbour_count) {
    char key[256];
    snprintf(key, sizeof(key), "node_%s_neighbours", node_id);
    
    redisReply *reply = redisCommand(context, "SMEMBERS %s", key);
    if (reply == NULL || reply->type != REDIS_REPLY_ARRAY) {
        if (reply) freeReplyObject(reply);
        *neighbour_count = 0;
        return NULL;
    }
    
    int count = reply->elements;
    int *neighbor_list = malloc(sizeof(int) * count);
    if (neighbor_list == NULL) {
        freeReplyObject(reply);
        *neighbour_count = 0;
        return NULL;
    }
    
    for (int i = 0; i < count; i++) {
        neighbor_list[i] = atoi(reply->element[i]->str);
    }
    
    *neighbour_count = count;
    freeReplyObject(reply);
    return neighbor_list;
}

// Comparator for sorting node IDs
int compare_node_ids(const void *a, const void *b) {
    int id_a = *(int *)a;
    int id_b = *(int *)b;
    return id_a - id_b;
}

int main(int argc, char *argv[]) {
    if (argc < 5) {
        printf("Usage: %s <server_ip> <start_node> <end_node> <username>\n", argv[0]);
        printf("Example: %s lhotse4 0 99999 mmanjee\n", argv[0]);
        return 1;
    }
    
    const char *server_ip = argv[1];
    int start_node = atoi(argv[2]);
    int end_node = atoi(argv[3]);
    const char *username = argv[4];
    
    printf("================================================\n");
    printf("VERIFICATION (C Program - Same approach as coloring)\n");
    printf("================================================\n");
    printf("Server: %s\n", server_ip);
    printf("Node range: %d to %d\n", start_node, end_node);
    printf("\n");
    
    // Connect to Redis
    redisContext *context = redisConnect(server_ip, 6379);
    if (context == NULL || context->err) {
        if (context) {
            fprintf(stderr, "Redis connection error: %s\n", context->errstr);
        } else {
            fprintf(stderr, "Connection error: can't allocate Redis context\n");
        }
        return 1;
    }
    printf("Connected to Redis server: %s\n\n", server_ip);
    
    // Step 1: Fetch all keys using KEYS command (same as coloring code)
    printf("Step 1: Fetching all node keys using KEYS command...\n");
    redisReply *keys_reply = redisCommand(context, "KEYS node_*_neighbours");
    if (keys_reply == NULL || keys_reply->type != REDIS_REPLY_ARRAY) {
        fprintf(stderr, "Failed to fetch keys\n");
        if (keys_reply) freeReplyObject(keys_reply);
        redisFree(context);
        return 1;
    }
    
    printf("Found %zu keys\n", keys_reply->elements);
    
    // Step 2: Filter keys by node ID range and collect valid node IDs
    int *valid_node_ids = malloc(sizeof(int) * keys_reply->elements);
    int valid_count = 0;
    
    for (size_t i = 0; i < keys_reply->elements; i++) {
        int node_id = get_node_id(keys_reply->element[i]->str);
        if (node_id >= start_node && node_id <= end_node) {
            valid_node_ids[valid_count++] = node_id;
        }
    }
    
    freeReplyObject(keys_reply);
    printf("Valid nodes in range: %d\n\n", valid_count);
    
    if (valid_count == 0) {
        printf("ERROR: No valid nodes found in range\n");
        free(valid_node_ids);
        redisFree(context);
        return 1;
    }
    
    // Step 3: Fetch colors, statuses, and neighbors for valid nodes
    printf("Step 2: Fetching colors, statuses, and neighbors...\n");
    NodeInfo *nodes = malloc(sizeof(NodeInfo) * valid_count);
    int colored_count = 0;
    
    for (int i = 0; i < valid_count; i++) {
        char node_id_str[32];
        snprintf(node_id_str, sizeof(node_id_str), "%d", valid_node_ids[i]);
        
        // Get status - skip if uncolored
        int status = get_node_status(context, node_id_str);
        if (status == 0) {
            continue; // Skip uncolored nodes
        }
        
        // Get color
        int color = get_node_color(context, node_id_str);
        if (color == -1) {
            continue; // Skip if color not found
        }
        
        // Get neighbors
        int neighbor_count = 0;
        int *neighbors = get_all_neighbours(context, node_id_str, &neighbor_count);
        
        nodes[colored_count].node_id = valid_node_ids[i];
        nodes[colored_count].color = color;
        nodes[colored_count].neighbors = neighbors;
        nodes[colored_count].neighbor_count = neighbor_count;
        colored_count++;
    }
    
    free(valid_node_ids);
    printf("Colored nodes found: %d\n\n", colored_count);
    
    if (colored_count == 0) {
        printf("ERROR: No colored nodes found\n");
        free(nodes);
        redisFree(context);
        return 1;
    }
    
    // Step 4: Create a lookup map for fast neighbor color access
    printf("Step 3: Building color lookup map...\n");
    int max_node_id = end_node;
    int *color_map = calloc(max_node_id + 1, sizeof(int));
    int *has_color = calloc(max_node_id + 1, sizeof(int));
    
    for (int i = 0; i < colored_count; i++) {
        if (nodes[i].node_id <= max_node_id) {
            color_map[nodes[i].node_id] = nodes[i].color;
            has_color[nodes[i].node_id] = 1;
        }
    }
    printf("Color map built\n\n");
    
    // Step 5: Verify coloring - check for conflicts
    printf("Step 4: Verifying coloring...\n");
    int conflict_count = 0;
    int verified_count = 0;
    
    for (int i = 0; i < colored_count; i++) {
        int node_id = nodes[i].node_id;
        int node_color = nodes[i].color;
        
        for (int j = 0; j < nodes[i].neighbor_count; j++) {
            int neighbor_id = nodes[i].neighbors[j];
            
            // Skip if neighbor is outside our range or not colored
            if (neighbor_id < start_node || neighbor_id > end_node || !has_color[neighbor_id]) {
                continue;
            }
            
            int neighbor_color = color_map[neighbor_id];
            
            // Check for conflict (same color as neighbor)
            if (node_color == neighbor_color) {
                // Only report once per pair (node_id < neighbor_id)
                if (node_id < neighbor_id) {
                    printf("CONFLICT: Node %d (color=%d) conflicts with neighbor %d (color=%d)\n",
                           node_id, node_color, neighbor_id, neighbor_color);
                    conflict_count++;
                }
            }
        }
        verified_count++;
        
        // Progress indicator
        if ((i + 1) % 10000 == 0) {
            printf("  Progress: %d/%d nodes verified...\n", i + 1, colored_count);
        }
    }
    
    // Cleanup
    for (int i = 0; i < colored_count; i++) {
        if (nodes[i].neighbors) {
            free(nodes[i].neighbors);
        }
    }
    free(nodes);
    free(color_map);
    free(has_color);
    redisFree(context);
    
    // Print results
    printf("\n");
    printf("================================================\n");
    if (conflict_count == 0) {
        printf("VERIFICATION SUCCESSFUL\n");
    } else {
        printf("VERIFICATION FAILED\n");
    }
    printf("================================================\n");
    printf("Total nodes verified: %d\n", verified_count);
    printf("Incorrectly colored nodes: %d\n", conflict_count);
    printf("================================================\n");
    
    return (conflict_count == 0) ? 0 : 1;
}

