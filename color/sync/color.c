#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <hiredis/hiredis.h>
#include <unistd.h>
#include <time.h>
typedef struct {
    char lock_key_1[128];  // Change from char** to char[] (array of chars)
    char lock_key_2[128];
    char turn_key[128];
    char node_name[128];
    
    
} ClientGraphPetersonLock;



  /*
        Example:
            nodeName = "15"
            neighborName = "34"
            nodeFlagVar = "flag15_34_15"
            neighborFlagVar = "flag15_34_34"
            turnVar = "turn15_34"

        flag15_34_15            flag15_34_34
        +-----+    turn15_34   +-----+
        | 15  |----------------| 34  |
        +-----+                +-----+
     */

int getMinimalValueNotInArray(int *arr, int arrLength, int lowerBound, int upperBound) {
    int range = upperBound - lowerBound + 1;
    
    if (range <= 0) {
        fprintf(stderr, "Invalid range: lowerBound=%d, upperBound=%d\n", lowerBound, upperBound);
        exit(EXIT_FAILURE);
    }
        // Dynamically allocate memory for the used values array
    int *usedValues = (int *)calloc(range, sizeof(int));
    if (usedValues == NULL) {
        fprintf(stderr, "Memory allocation failed\n");
        exit(EXIT_FAILURE); // Exit with an error
    }

    // Mark used values within the range [lowerBound, upperBound]
    for (int i = 0; i < arrLength; i++) {
        if (arr[i] >= lowerBound && arr[i] <= upperBound) {
            usedValues[arr[i] - lowerBound] = 1;
        }
    }

    // Find the first available unused value
    for (int i = lowerBound; i <= upperBound; i++) {
        if (usedValues[i - lowerBound] == 0) {
            free(usedValues); // Free the allocated memory
            return i;
        }
    }

    // Debug message: range too small
    printf("getMinimalValueNotInArray: error: the range is too small\n");

    // Free the allocated memory and recursively call with an extended range
    free(usedValues);
    return getMinimalValueNotInArray(arr, arrLength, lowerBound, upperBound + arrLength + 1);
}

void log_wait() {
    // Get current time
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    
    // Format time as YYYY-MM-DD HH:MM:SS
    char time_buffer[20];
    strftime(time_buffer, sizeof(time_buffer), "%Y-%m-%d %H:%M:%S", t);
    
    // Get the hostname
    char hostname[100];
    gethostname(hostname, sizeof(hostname));
    
    // Construct the log file name
    char log_filename[150];
    snprintf(log_filename, sizeof(log_filename), "%s_throughput.txt", hostname);
    
    // Log the write operation with timestamp
    FILE *log_file = fopen(log_filename, "a");
    if (log_file) {
        fprintf(log_file, "Wait command at %s\n", time_buffer);
        fclose(log_file);
    } else {
        fprintf(stderr, "Failed to open log file for writing\n");
    }
}

void log_write_end() {
    // Get current time
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    
    // Format time as YYYY-MM-DD HH:MM:SS
    char time_buffer[20];
    strftime(time_buffer, sizeof(time_buffer), "%Y-%m-%d %H:%M:%S", t);
    
    // Get the hostname
    char hostname[100];
    gethostname(hostname, sizeof(hostname));
    
    // Construct the log file name
    char log_filename[150];
    snprintf(log_filename, sizeof(log_filename), "%s_throughput.txt", hostname);
    
    // Log the write operation with timestamp
    fprintf(stdout, "\nWrite command executed at %s\n", time_buffer);
}

void log_write_start() {
    // Get current time
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    
    // Format time as YYYY-MM-DD HH:MM:SS
    char time_buffer[20];
    strftime(time_buffer, sizeof(time_buffer), "%Y-%m-%d %H:%M:%S", t);
    
    // Get the hostname
    char hostname[100];
    gethostname(hostname, sizeof(hostname));
    
    // Construct the log file name
    char log_filename[150];
    snprintf(log_filename, sizeof(log_filename), "%s_throughput.txt", hostname);
    
    // Log the write operation with timestamp
   
  
    fprintf(stdout, "\nWrite command Started at %s\n", time_buffer);
      
    
}

void log_read() {
    // Get current time
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    
    // Format time as YYYY-MM-DD HH:MM:SS
    char time_buffer[20];
    strftime(time_buffer, sizeof(time_buffer), "%Y-%m-%d %H:%M:%S", t);
    
    // Get the hostname
    char hostname[100];
    gethostname(hostname, sizeof(hostname));
    
    // Construct the log file name
    char log_filename[150];
    snprintf(log_filename, sizeof(log_filename), "%s_throughput.txt", hostname);
    
    // Log the read operation with timestamp
    FILE *log_file = fopen(log_filename, "a");
    if (log_file) {
        fprintf(log_file, "Read command at %s\n", time_buffer);
        fclose(log_file);
    } else {
        fprintf(stderr, "Failed to open log file for reading\n");
    }
}

redisReply *write_with_wait(redisContext *c, char *required_replicas, char *timeout_ms, char* command_name, char* key, char* value) {
    redisReply *reply;
    int acknowledged_replicas = 0;
    int required = atoi(required_replicas);
    log_write_start();

    fprintf(stdout, "\n Command %s with key  %s and value %s \n", command_name, key, value);
    fflush(stdout);
      
    // Send the write command ONCE (don't retry SET)
        reply = redisCommand(c, "%s %s %s", command_name, key, value);
        if (!reply) {
            fprintf(stderr, "Failed to execute command: %s\n", c->errstr);
            return NULL;
        }
    
    // Check if SET command succeeded
    if (reply->type == REDIS_REPLY_ERROR) {
        fprintf(stderr, "Command failed: %s\n", reply->str);
        freeReplyObject(reply);
        return NULL;
    }
    
    // Check if SET returned OK
    if (reply->type == REDIS_REPLY_STATUS && strcmp(reply->str, "OK") != 0) {
        fprintf(stderr, "SET command returned unexpected status: %s\n", reply->str);
        freeReplyObject(reply);
        return NULL;
    }
    
    freeReplyObject(reply);

    // FIX: If required replicas is 0, skip WAIT (no replication needed)
    if (required == 0) {
        acknowledged_replicas = 0;
    } else {
        int retry_count = 0; // Track retries for partial acks (when we get some but not enough)
        
        // Retry WAIT command (but NOT the SET command) until we get enough acks
        // No max retry limit when acknowledged_replicas == 0 (keep retrying indefinitely)
        // Max retry limit of 3 when acknowledged_replicas > 0 but < required
        do {
        // Wait for replicas using WAIT command
        reply = redisCommand(c, "WAIT %s %s", required_replicas, timeout_ms);
        
        if (!reply) {
            fprintf(stderr, "WAIT command failed: %s\n", c->errstr);
                // If WAIT fails but SET succeeded, we can still proceed
                acknowledged_replicas = 0;
                break;
            }
            
            if (reply->type == REDIS_REPLY_ERROR) {
                fprintf(stderr, "WAIT command error: %s\n", reply->str);
                freeReplyObject(reply);
                // If WAIT fails but SET succeeded, proceed anyway
                acknowledged_replicas = 0;
                break;
        }

        acknowledged_replicas = reply->integer;
            fprintf(stdout, "\nRequired Replicas: %d, Acknowledged Replicas: %d", 
                    required, acknowledged_replicas);
            fflush(stdout);
        
        freeReplyObject(reply);

            // If we got enough acks, break
            if (acknowledged_replicas >= required) {
                break;
            }
            
            // If we got 0 acks, keep retrying indefinitely (no max retry limit)
            // This handles cases where replication is temporarily slow but will eventually catch up
            if (acknowledged_replicas == 0) {
                usleep(100000); // 100ms delay before retry
                continue; // Keep retrying without max limit
            }
            
            // If we got some acks but not enough, apply max retry limit
            retry_count++;
            if (retry_count >= 3) {
                fprintf(stderr, "\nWARNING: WAIT timed out after %d retries. Got %d/%d acks. Proceeding anyway.\n",
                        3, acknowledged_replicas, required);
                break;
            }
            
            // Small delay before retry
            usleep(100000); // 100ms delay
            
    } while (acknowledged_replicas < required);
    }
    
    log_write_end();
    
    // Return a dummy success reply instead of NULL
    redisReply *success_reply = (redisReply *)malloc(sizeof(redisReply));
    success_reply->type = REDIS_REPLY_STATUS;
    success_reply->str = strdup("OK");
    success_reply->len = 2;
    return success_reply;
}

void print_locks_array(ClientGraphPetersonLock *locks_array, int num_neighbors) {
    for (int i = 0; i < num_neighbors; i++) {
        printf("Lock %d:\n", i + 1);
        printf("  lock_key_1: %s\n", locks_array[i].lock_key_1);
        printf("  lock_key_2: %s\n", locks_array[i].lock_key_2);
        printf("  turn_key: %s\n", locks_array[i].turn_key);
    }
}

void acquire_lock(redisContext *context, ClientGraphPetersonLock *lock,const char *log_file_path,char *num_of_replicas,char *timeout) {
    redisReply *my_flag, *turn_var, *other_flag, *turn_var_new;

    // Set the first flag
        my_flag = write_with_wait(context, num_of_replicas, timeout, "SET", lock->lock_key_1, "1");
    if (!my_flag) {
        fprintf(stderr, "ERROR: Failed to set lock_key_1: %s\n", lock->lock_key_1);
        return; // Exit if write failed
    }
    freeReplyObject(my_flag);
        
    // Set the turn variable
    turn_var = write_with_wait(context, num_of_replicas, timeout, "SET", lock->turn_key, lock->node_name);
    if (!turn_var) {
        fprintf(stderr, "ERROR: Failed to set turn_key: %s\n", lock->turn_key);
        return;
    }
    freeReplyObject(turn_var);

    // Get the other flag and turn variable
    other_flag = redisCommand(context, "GET %s", lock->lock_key_2);
    if (!other_flag) {
        fprintf(stderr, "ERROR: Failed to GET lock_key_2: %s\n", lock->lock_key_2);
        return;
    }
        log_read();
    
        turn_var_new = redisCommand(context, "GET %s", lock->turn_key);
    if (!turn_var_new) {
        fprintf(stderr, "ERROR: Failed to GET turn_key: %s\n", lock->turn_key);
        freeReplyObject(other_flag);
        return;
    }
        log_read();

    // FIX: Add NULL checks before accessing ->str
    while (other_flag != NULL && other_flag->type != REDIS_REPLY_NIL && other_flag->str != NULL &&
           turn_var_new != NULL && turn_var_new->type != REDIS_REPLY_NIL && turn_var_new->str != NULL &&
                   strcmp(other_flag->str, "1") == 0 &&
           strcmp(turn_var_new->str, lock->node_name) == 0) {

        // Free old replies before getting new ones
        freeReplyObject(turn_var_new);
        freeReplyObject(other_flag);

                turn_var_new = redisCommand(context, "GET %s", lock->turn_key);
                log_read();
        other_flag = redisCommand(context, "GET %s", lock->lock_key_2);
                log_read();

        // Check if new replies are NULL or errors
        if (!turn_var_new || !other_flag) {
            fprintf(stderr, "ERROR: GET commands failed in busy-wait loop\n");
            break;
        }
        
        // If either key doesn't exist (NIL), break the loop
        if (other_flag->type == REDIS_REPLY_NIL || turn_var_new->type == REDIS_REPLY_NIL) {
            break;
        }
                   }

    // Clean up
    if (other_flag) freeReplyObject(other_flag);
    if (turn_var_new) freeReplyObject(turn_var_new);
}

void release_lock(redisContext *context, ClientGraphPetersonLock *lock,char *num_of_replicas, char *timeout) {
    redisReply *reply;

    // Delete the first lock key
    printf("\n in the release block the lock name is : %s \n", lock->lock_key_1);
    reply = write_with_wait(context, num_of_replicas,timeout, "SET" ,lock->lock_key_1, "0" );
    
   
    // if (reply == NULL || reply->type == REDIS_REPLY_ERROR) {
    //     fprintf(stderr, "Error: Failed to delete lock_key_1: %s\n", lock->lock_key_1);
    // }
    // if (reply) {
    //     freeReplyObject(reply);
    // }

    
}

// Function to get all neighbors of a node using SMEMBERS
char** get_all_neighbours(redisContext *context, const char *node_name, int *neighbour_count) {
    // Generate the Redis key for the neighbors
    if (neighbour_count <= 0) {
        fprintf(stderr, "Error: No neighbors found for node %s\n", node_name);
       
        return NULL;
    }
    char key[256];
    snprintf(key, sizeof(key), "%s_neighbours", node_name);

    // Send the Redis SMEMBERS command
    redisReply *reply = redisCommand(context, "SMEMBERS %s", key);
    log_read();
    // Check if the key exists and if the reply is valid
    if (reply == NULL || reply->type == REDIS_REPLY_NIL) {
        fprintf(stderr, "Error: Node %s does not exist or has no neighbors.\n", node_name);
        freeReplyObject(reply);
        return NULL;
    }

    // Check if the reply contains an array
    if (reply->type != REDIS_REPLY_ARRAY) {
        fprintf(stderr, "Error: Unexpected reply type for node %s neighbors.\n", node_name);
        freeReplyObject(reply);
        return NULL;
    }

    // Allocate memory for the neighbor list
    int count = reply->elements;
    char **neighbor_list = malloc(sizeof(char*) * count);
    if (neighbor_list == NULL) {
        fprintf(stderr, "Error: Memory allocation failed.\n");
        freeReplyObject(reply);
        return NULL;
    }

    // Copy neighbors from the reply into the list
    for (int i = 0; i < count; i++) {
        neighbor_list[i] = strdup(reply->element[i]->str);
        // printf("\n %s neighboours of %s \n", neighbor_list[i], node_name);
    }

    *neighbour_count = count; // Return the number of neighbors
    freeReplyObject(reply);
    printf("No of neighbours %d",count);
    return neighbor_list;
}

// Comparator function for numerical sorting
int compare_neighbours(const void *a, const void *b) {
    // Convert the strings to integers and compare them
    int num_a = atoi(*(const char **)a);
    int num_b = atoi(*(const char **)b);
    return num_a - num_b;
}

// Function to sort the neighbor list numerically
void sort_neighbours(char **neighbour_list, int neighbour_count) {
    qsort(neighbour_list, neighbour_count, sizeof(char *), compare_neighbours);
}


int get_node_color(redisContext *context, const char *node_name) {
    char key[256];
    snprintf(key, sizeof(key), "node_%s_color", node_name);
    redisReply *reply = redisCommand(context, "GET %s", key);
    if (reply == NULL || reply->type == REDIS_REPLY_NIL) {
        fprintf(stderr, "Error: Node %s color not found.\n", node_name);
        return -1; // Return -1 if not found
    }
    log_read();
    
    return atoi(reply->str);
}


int check_boundary_node(redisContext *context, const char *node_name, int last_node_id_of_last_task, int first_node_id_of_first_task)

{
    char key[256];
    snprintf(key, sizeof(key), "%s_neighbours", node_name);

    // Send the Redis SMEMBERS command
    redisReply *reply = redisCommand(context, "SMEMBERS %s", key);
    log_read();
    int count = reply->elements;
    char **neighbor_list = malloc(sizeof(char*) * count);
    
    

    // Copy neighbors from the reply into the list
    for (int i = 0; i < count; i++) {
        neighbor_list[i] = strdup(reply->element[i]->str);
        
        int nbr_id_int = atoi(neighbor_list[i]);
    
        if(nbr_id_int < first_node_id_of_first_task || nbr_id_int > last_node_id_of_last_task){
            // So the node has a neigbhour in another partition
            // printf(" \n %s  is a boundary node ", node_name);

            return 1;
            }

        // printf("\n %s neighboours of %s \n", neighbor_list[i], node_name);
    }
    // printf("\n %s  is not a boundary node ",node_name);
     // Return the number of neighbors
    freeReplyObject(reply);
    printf("Boundary nodes check completed");
    return 0;
}

void set_node_color(redisContext *context, const char *node_name, int color, const char *log_file_path, char *num_of_replicas, char *timeout) {
    char key[256];
    snprintf(key, sizeof(key), "%s_color", node_name);
    
    // Convert the integer color to string
    char color_str[10];
    snprintf(color_str, sizeof(color_str), "%d", color);

    char status[256];
    snprintf(status, sizeof(status), "%s_status", node_name);

    redisReply *reply = write_with_wait(context, num_of_replicas, timeout , "SET" , key, color_str);
    redisReply *status_reply = write_with_wait(context, num_of_replicas, timeout , "SET" , status, "1");
    
    if (reply == NULL || reply->type == REDIS_REPLY_ERROR) {
        if (reply != NULL) {
            // Manually free custom allocated reply
            if (reply->str) free(reply->str);
            free(reply);
        }
        if (status_reply != NULL) {
            if (status_reply->str) free(status_reply->str);
            free(status_reply);
        }
        return;
    }

    fprintf(stdout, "Colored Node %s as %s.\n", node_name, color_str);

    // Manually free custom allocated replies
    if (reply != NULL) {
        if (reply->str) free(reply->str);
        free(reply);
    }
    if (status_reply != NULL) {
        if (status_reply->str) free(status_reply->str);
        free(status_reply);
    }
}

// void set_node_color(redisContext *context, const char *node_name, int color, const char *log_file_path, char *num_of_replicas, char *timeout) {
//     char key[256];
//     snprintf(key, sizeof(key), "%s_color", node_name);
    
//     // Convert the integer color to string
//     char color_str[10];
//     snprintf(color_str, sizeof(color_str), "%d", color);
    

//     char status[256];
//     snprintf(status, sizeof(status), "%s_status", node_name);

//     // Open the log file in append mode
//     // FILE *log_file = fopen(log_file_path, "a");
//     // if (log_file == NULL) {
//     //     fprintf(stderr, "Error: Failed to open log file for asdfasdfasdf writing: %s\n", log_file_path);
//     //     return;
//     // }

//     // // Log node name and color to the log file
//     // fprintf(log_file, "Setting color for node: %s, Color: %d\n", node_name, color);

//     // Set the color in Redis
//     // redisReply *reply = redisCommand(context, "SET %s %s", key, color_str);
//     redisReply *reply = write_with_wait(context, num_of_replicas, timeout , "SET" , key, color_str);
//     redisReply *status_reply = write_with_wait(context, num_of_replicas, timeout , "SET" , status, "1");
//     if (reply == NULL || reply->type == REDIS_REPLY_ERROR) {
//         // fprintf(stderr, "Error: Failed to set color for node %s.\n", node_name);
//         // // Log the error to the log file
//         // fprintf(log_file, "Error: Failed to set color for node: %s\n", node_name);
//         if (reply != NULL) {
//             freeReplyObject(reply);
//         }
//         // fclose(log_file); // Close the log file
//         return; // Exit the function
//     }

//     // Log success to the log file
//     // fprintf(log_file, "Successfully set color for node: %s, Color: %d\n", node_name, color);
//     fprintf(stdout, "Colored Node %s as %s.\n", node_name, color_str);

//     if (reply != NULL) {
//         freeReplyObject(reply);
//     }
//     if (status_reply != NULL) {
//         freeReplyObject(status_reply);
//     }
//     freeReplyObject(reply);
//     // fclose(log_file); // Close the log file
// }


int get_node_id(const char *node_name) {
    const char *prefix = "node_";
    size_t prefix_len = strlen(prefix);

    // Check if the input starts with the prefix "node_"
    if (strncmp(node_name, prefix, prefix_len) != 0) {
        fprintf(stderr, "Error: Invalid node name format: %s\n", node_name);
        return -1; // Return an error value
    }

    // Extract the numeric part of the node name and convert to integer
    int node_id = atoi(node_name + prefix_len);
    return node_id;
}
char* extract_number_from_string(const char *str) {
    // Find the position of the underscore
    const char *underscore_pos = strchr(str, '_');
    if (underscore_pos == NULL) {
        return NULL;  // Return NULL if there's no underscore in the string
    }
    
    // Allocate memory to hold the number string (after the underscore)
    char *result = (char*)malloc(strlen(underscore_pos) * sizeof(char));
    if (result == NULL) {
        return NULL;  // Return NULL if memory allocation fails
    }
    
    // Copy the part of the string after the underscore
    strcpy(result, underscore_pos + 1);  // Skip the underscore itself

    return result;
}

int get_status(redisContext *context, const char *node_name) {
    char key[256];
    
    snprintf(key, sizeof(key), "node_%s_status", node_name);
    redisReply *reply = redisCommand(context, "GET %s", key);
    if (reply == NULL) {
        printf("error");
        fprintf(stderr, "Error: Failed to execute GET command for node %s.\n", node_name);
        // Handle the error as appropriate, possibly by reconnecting
        return 0;
    }
    if (reply->type == REDIS_REPLY_NIL) {
        // Key does not exist
       
        freeReplyObject(reply);
        return 0;
    }
    if (reply->type != REDIS_REPLY_STRING) {
        fprintf(stderr, "Error: Unexpected reply type %d for node %s.\n", reply->type, node_name);
        freeReplyObject(reply);
        return 0;
    }
    
    int status = atoi(reply->str);
    
    return status;
}

void read_color_of_neighbors(redisContext *context,
    const char *node_id,
    int first_node_id_of_first_task,
    int last_node_id_of_last_task,
    char **node_nbr_list_sorted,
    int *nbr_color_list,
    int num_neighbors,
    ClientGraphPetersonLock *locks_array,
    const char *log_file_path,
    char *num_of_replicas, 
    char *timeout,
    int *num_locks) { // New pointer for tracking number of locks

// Initialize the lock counter
    *num_locks = 0;  // Set the initial count to 0

    for (int nbr = 0; nbr < num_neighbors; nbr++) {
        const char *nbr_id = node_nbr_list_sorted[nbr];
        int nbr_id_int = atoi(nbr_id);
        int node_id_int = get_node_id(node_id);
        char *char_node = extract_number_from_string(node_id);

        // Get the color of the neighbor node FIRST (before acquiring locks)
        int nbr_color = get_node_color(context, nbr_id);
        
        // Check if neighbor is uncolored
        // Note: color 0 is a VALID color that can be assigned, so we only check status
        // status == 0 means uncolored, status == 1 means colored (even if color is 0)
        // nbr_color == -1 means key doesn't exist (also uncolored)
        int status = get_status(context, nbr_id);
        int is_uncolored = (status == 0 || nbr_color == -1);
        
        // CRITICAL FIX: Acquire locks for ALL uncolored neighbors, regardless of partition
        // This prevents race conditions when two clients process adjacent nodes simultaneously
        if (is_uncolored) {
            char bothId[64];
            if (nbr_id_int < node_id_int) {
                snprintf(bothId, sizeof(bothId), "%s_%s", nbr_id, char_node);
            } else {
                snprintf(bothId, sizeof(bothId), "%s_%s", char_node, nbr_id);
            }

        // Create and store the lock in the locks array
        ClientGraphPetersonLock *lock = &locks_array[*num_locks]; // Reference the specific lock in the array
        snprintf(lock->lock_key_1, sizeof(lock->lock_key_1), "flag_%s_%s", bothId, char_node);
        snprintf(lock->lock_key_2, sizeof(lock->lock_key_2), "flag_%s_%s", bothId, nbr_id);
        snprintf(lock->turn_key, sizeof(lock->turn_key), "turn_%s", bothId);
        snprintf(lock->node_name, sizeof(lock->node_name), "%s", char_node);
        
        
        printf("\nSetting Up Locks for %s and %s\n", char_node,nbr_id);    
                printf("%s\n", lock->lock_key_1);
                printf("%s\n", lock->lock_key_2);
                printf("%s\n", lock->turn_key);
                printf("%s\n", lock->node_name);

        // Acquire the lock
        acquire_lock(context, lock, log_file_path, num_of_replicas, timeout);
        (*num_locks)++;     
        // Increment the lock counter
         // Update the counter each time a lock is acquired
            
            // CRITICAL FIX: Re-read neighbor color AFTER acquiring lock
            // The neighbor might have colored itself while we were waiting for the lock
            nbr_color = get_node_color(context, nbr_id);
        }

        nbr_color_list[nbr] = nbr_color;
        printf(" \n neigbhour color read: %d\n", nbr_color);
        
        // Free the extracted node number string
        if (char_node != NULL) {
            free(char_node);
        }
}
}

void set_status(redisContext *context, const char *node_name ){
    char key[256];
    snprintf(key, sizeof(key), "%s_status", node_name);
   
    redisReply *reply = redisCommand(context, "SET %s %s", key, "1");
    
    if (reply == NULL || reply->type == REDIS_REPLY_ERROR) {
        fprintf(stderr, "Error: Failed to set colored status for node %s.\n", node_name);
        if (reply != NULL) {
            freeReplyObject(reply);
        }
        return; // Exit the function
    }

    freeReplyObject(reply);
}




void process_node(redisContext *context, const char *node_name, 
                 int first_node_id_of_first_task, int last_node_id_of_last_task, const char *log_file_path,char *num_of_replicas, char *timeout) {
    int neighbour_count = 0;
    int num_locks = 0; 
    
    fprintf(stdout, "Coloring Node %s.\n", node_name);
    // Get all neighbors of the specified node
    char **neighbour_list = get_all_neighbours(context, node_name, &neighbour_count);
    int boundary_node =  check_boundary_node(context, node_name, last_node_id_of_last_task, first_node_id_of_first_task);

    // FILE *log_file = fopen(log_file_path, "w");
    // printf("%s",log_file_path);
    //     if (log_file == NULL) {
    //         fprintf(stderr, "00987098709879879879 Error: Failed to open log file for writing: %s\n", log_file_path);
    //         return;
    //     }
    // printf("\n Boundary node status of %s is %d \n", node_name,boundary_node);
    if (neighbour_list == NULL || neighbour_count == 0) {
        printf("\n No neighbors found for node %s\n", node_name);
        
    }

    // Sort the neighbors numerically
    sort_neighbours(neighbour_list, neighbour_count);

    
    // fprintf(log_file,"Sorted neighbors of %s:\n", node_name);
    // for (int i = 0; i < neighbour_count; i++) {
    //     // printf(" %s\n", neighbour_list[i]);
    //     // fprintf(log_file, "%s\n", neighbour_list[i]);
        
    // }

    // Allocate memory for locks and neighbor color list
    ClientGraphPetersonLock *locks_array = malloc(neighbour_count * sizeof(ClientGraphPetersonLock));
    int *nbr_color_list = (int *)malloc(neighbour_count * sizeof(int));
    int status;
    if (nbr_color_list == NULL) {
        printf("\nMemory allocation error for nbr_color_list\n");
        free(neighbour_list);
    }

    // Read the colors of the neighbors
    read_color_of_neighbors(context, node_name, first_node_id_of_first_task, last_node_id_of_last_task,
                            neighbour_list, nbr_color_list, neighbour_count, locks_array,log_file_path, num_of_replicas , timeout,&num_locks);

    // Print neighbor colors
    // for (int i = 0; i < neighbour_count; i++) {
    //     printf("%d\n", nbr_color_list[i]);
    // }

    // Determine the minimal unused color
    printf("\nnumber of lock is %d\n", num_locks);
    int new_color = getMinimalValueNotInArray(nbr_color_list, neighbour_count, 0, 1000);

    // Set the new color for the node
    
    set_node_color(context, node_name, new_color,log_file_path,num_of_replicas,timeout);
    
    
    
    // Release locks
   
    for (int i = 0; i < num_locks; i++) {
        // printf("\n locks_array element no %d, lock_key_1 is %s\n",locks_array[i]lock_key_1);
        release_lock(context, &locks_array[i], num_of_replicas, timeout);
    }

    // Free allocated memory
    free(neighbour_list);
    free(nbr_color_list);
    free(locks_array);
}



int compare_keys(const void *a, const void *b) {
    const char *key_a = *(const char **)a;
    const char *key_b = *(const char **)b;

    // Extract numeric parts from the keys
    int num_a = atoi(strchr(key_a, '_') + 1); // Find '_' and convert the number after it
    int num_b = atoi(strchr(key_b, '_') + 1);

    return num_a - num_b; // Compare numerically
}

const char **fetch_keys(redisContext *context, const char *pattern, int *key_count) {
    redisReply *reply = redisCommand(context, "KEYS %s", pattern);
    log_read();
    if (reply == NULL || reply->type != REDIS_REPLY_ARRAY) {
        // printf("Failed to fetch keys with pattern %s\n", pattern);
        if (reply) freeReplyObject(reply);
        return NULL;
    }

    *key_count = reply->elements;

    const char **keys = malloc(*key_count * sizeof(char *));
    if (keys == NULL) {
        // printf("Memory allocation error for keys array\n");
        freeReplyObject(reply);
        return NULL;
    }

    for (size_t i = 0; i < reply->elements; i++) {
        char *key_with_suffix = strdup(reply->element[i]->str); // Duplicate the string
        if (!key_with_suffix) {
            printf("Memory allocation error for key duplication\n");
            for (size_t j = 0; j < i; j++) free((void *)keys[j]);
            free(keys);
            freeReplyObject(reply);
            return NULL;
        }

        // Remove `_neighbours` suffix, if present
        char *suffix = strstr(key_with_suffix, "_neighbours");
        if (suffix) {
            *suffix = '\0'; // Terminate the string before the suffix
        }

        keys[i] = key_with_suffix;
    }

    // Sort the keys numerically by the extracted numeric part
    qsort(keys, *key_count, sizeof(char *), compare_keys);

    freeReplyObject(reply);
    return keys;
}

void set_status_to_monitor(redisContext *context, const char *hostname) {
    char key[256];
    snprintf(key, sizeof(key), "%s_status", hostname);

    // Get the current Unix timestamp
    time_t now = time(NULL);
    if (now == -1) {
        fprintf(stderr, "Error: Failed to get current time.\n");
        return;
    }

    // Convert timestamp to human-readable time (hh:mm:ss)
    struct tm *tm_info;
    char time_str[32];
    tm_info = localtime(&now);
    strftime(time_str, sizeof(time_str), "%H:%M:%S", tm_info);  // hh:mm:ss format

    // Print the time in hh:mm:ss format
    printf("Time is: %s\n", time_str);

    // Store the formatted time in Redis
    redisReply *reply = redisCommand(context, "SET %s %s", key, time_str);

    if (reply == NULL || reply->type == REDIS_REPLY_ERROR) {
        fprintf(stderr, "Error: Failed to set colored status for node %s.\n", hostname);
        if (reply != NULL) {
            freeReplyObject(reply);
        }
        return; // Exit the function
    }

    freeReplyObject(reply);
}

int main(int argc, char *argv[]) {
    if (argc < 5) {
        printf("Usage: %s <first_node_id_of_first_task> <last_node_id_of_last_task>\n", argv[0]);
        return 1;
    }
    
    // Parse command-line arguments
    int first_node_id_of_first_task = atoi(argv[1]);
    int last_node_id_of_last_task = atoi(argv[2]);
    char *ip = argv[3];
    const char *log_file_path = argv[4];
    const char *hostname = argv[5];
    char *num_of_replicas= argv[6];
    char *timeout = "10000" ;
    
    fprintf(stdout, "Coloring started");
    if (first_node_id_of_first_task > last_node_id_of_last_task) {
        printf("Error: first_node_id_of_first_task must be less than or equal to last_node_id_of_last_task.\n");
        return 1;
    }

    // Connect to Redis
    redisContext *context = redisConnect(ip, 6379);
    if (context == NULL || context->err) {
        if (context) {
            fprintf(stderr,"Redis connection error: %s\n", context->errstr);
        } else {
            fprintf(stderr,"Connection error: can't allocate Redis context\n");
        }
        return 1;
    }
    fprintf(stdout, "\n Connected to Redis Server");
    // Fetch keys from Redis
    int key_count = 0;
    const char **keys = fetch_keys(context, "node_*_neighbours", &key_count);
    fprintf(stdout, "\n Keys Fetched");
    fflush(stdout);
    if (keys == NULL || key_count == 0) {
        fprintf(stdout, "Error: No keys found.\n");
        fflush(stdout);
        redisFree(context);
        return 1;
    }
    fprintf(stdout, "key_count = %d\n", key_count);
    fflush(stdout);
    // for (int i = 0; i < key_count; i++) {
    // printf("Key %d: %s\n", i + 1, keys[i]);
    // }

    fprintf(stdout, "\nFetched all keys");    
    fflush(stdout);
    // printf("Processing nodes:\n");

    int total_processed_nodes = 0;  // Counter for processed nodes
    
    // Process each node - iterate through keys array and filter by partition range
    for (int i = 0; i < key_count; i++) {
        // Extract node ID from key (e.g., "node_123" -> 123)
        int node_id = get_node_id(keys[i]);
        if (node_id < 0) {
            // Invalid node format, skip
            free((void *)keys[i]);
            continue;
        }
        
        // Only process nodes in this client's partition range
        if (node_id >= first_node_id_of_first_task && node_id <= last_node_id_of_last_task) {
            fprintf(stdout, "\nProcessing node %s (ID: %d)\n", keys[i], node_id);
        process_node(context, keys[i], first_node_id_of_first_task, last_node_id_of_last_task,log_file_path,num_of_replicas, timeout);
        total_processed_nodes++;  // Increment the counter
        }
        
        free((void *)keys[i]); // Free the key string
    }
    fprintf(stdout, "\nColored all nodes");   
    // Print the total number of processed nodes
    // printf("Total nodes processed: %d\n", total_processed_nodes);

    // Free the keys array and Redis context
    free(keys);
    redisFree(context);
    redisContext *monitor_context = redisConnect("yangra101", 6379);
    set_status_to_monitor(monitor_context,hostname);
    return 0;
}