#include <time.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

enum {
    CUBIES = 7,
    PERMUTATIONS = 5040,
    ORIENTATIONS = 729,
    STATES = PERMUTATIONS * ORIENTATIONS,
    MOVES = 9
};

typedef struct {
    uint8_t p[CUBIES], o[CUBIES];
} state_t;

static uint8_t permutation_distance[PERMUTATIONS];
static uint8_t orientation_distance[ORIENTATIONS];
static uint16_t permutation_next[3][PERMUTATIONS];
static uint16_t orientation_next[3][ORIENTATIONS];
static const char* const move_names[MOVES] = { "R",  "R2", "R'", "B", "B2","B'", "D",  "D2", "D'" };
static const uint8_t inverse_move[MOVES] = { 2, 1, 0, 5, 4, 3, 8, 7, 6 };

static const uint8_t source[3][CUBIES] = {
    { 1, 4, 2, 0, 3, 5, 6 },
    { 0, 1, 2, 4, 5, 6, 3 },
    { 0, 2, 5, 3, 1, 4, 6 },
};

static const uint8_t twist[3][CUBIES] = {
    { 1, 2, 0, 2, 1, 0, 0 },
    { 0, 0, 0, 1, 2, 1, 2 },
    { 0, 0, 0, 0, 0, 0, 0 },
};

static state_t quarter_turn(state_t state, uint8_t face)
{
    state_t result;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t from = source[face][i];
        result.p[i] = state.p[from];
        result.o[i] = (uint8_t)((state.o[from] + twist[face][i]) % 3U);
    }
    return result;
}

static state_t apply_move(state_t state, uint8_t move)
{
    uint8_t turns = (uint8_t)(move % 3U + 1U);
    for (uint8_t i = 0; i < turns; ++i)
        state = quarter_turn(state, (uint8_t)(move / 3U));
    return state;
}

static uint32_t rank_state(const state_t* state)
{
    uint32_t p = 0, o = 0;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t smaller = 0;
        for (uint8_t j = (uint8_t)(i + 1U); j < CUBIES; ++j)
            if (state->p[j] < state->p[i])
                ++smaller;
        p = p * (CUBIES - i) + smaller;
    }
    for (uint8_t i = 0; i < 6; ++i)
        o = o * 3U + state->o[i];
    return p * ORIENTATIONS + o;
}

static void unrank_state(uint32_t rank, state_t* state)
{
    uint8_t available[CUBIES] = { 0, 1, 2, 3, 4, 5, 6 };
    uint32_t p = rank / ORIENTATIONS, o = rank % ORIENTATIONS, f = 720;
    uint8_t sum = 0;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t q = (uint8_t)(p / f);
        p %= f;
        state->p[i] = available[q];
        for (uint8_t j = q; j + 1U < CUBIES - i; ++j)
            available[j] = available[j + 1U];
        if (i < 5)
            f /= 6U - i;
    }
    for (uint8_t i = 6; i-- > 0;) {
        state->o[i] = (uint8_t)(o % 3U);
        sum = (uint8_t)(sum + state->o[i]);
        o /= 3U;
    }
    state->o[6] = (uint8_t)((3U - sum % 3U) % 3U);
}

static void build_transitions(void)
{
    state_t state;

    for (uint16_t p = 0; p < PERMUTATIONS; ++p) {
        unrank_state((uint32_t)p * ORIENTATIONS, &state);

        for (uint8_t face = 0; face < 3; ++face) {
            state_t next = quarter_turn(state, face);

            permutation_next[face][p] =
                (uint16_t)(rank_state(&next) / ORIENTATIONS);
        }
    }

    for (uint16_t o = 0; o < ORIENTATIONS; ++o) {
        unrank_state(o, &state);

        for (uint8_t face = 0; face < 3; ++face) {
            state_t next = quarter_turn(state, face);

            orientation_next[face][o] =
                (uint16_t)(rank_state(&next) % ORIENTATIONS);
        }
    }
}

static int build_permutation_distances(void)
{
    uint16_t queue[PERMUTATIONS];
    unsigned head = 0;
    unsigned tail = 0;

    memset(permutation_distance, UINT8_MAX,
        sizeof permutation_distance);

    permutation_distance[0] = 0;
    queue[tail++] = 0;

    while (head < tail) {
        uint16_t here = queue[head++];

        for (uint8_t face = 0; face < 3; ++face) {
            uint16_t next = here;

            for (uint8_t turn = 0; turn < 3; ++turn) {
                next = permutation_next[face][next];

                if (next >= PERMUTATIONS) {
                    fputs("invalid permutation transition\n", stderr);
                    return 0;
                }

                if (permutation_distance[next] == UINT8_MAX) {
                    permutation_distance[next] =
                        (uint8_t)(permutation_distance[here] + 1);

                    queue[tail++] = next;
                }
            }
        }
    }

    if (tail != PERMUTATIONS) {
        fprintf(stderr, "incomplete permutation BFS: %u\n", tail);
        return 0;
    }

    uint8_t maximum = 0;

    for (unsigned i = 0; i < PERMUTATIONS; ++i) {
        if (permutation_distance[i] > maximum)
            maximum = permutation_distance[i];
    }

    fprintf(stderr,
        "permutation BFS: visited=%u maximum=%u solved=%u\n",
        tail, (unsigned)maximum,
        (unsigned)permutation_distance[0]);
    return 1;
}

static int build_orientation_distances(void)
{
    uint16_t queue[ORIENTATIONS];
    unsigned head = 0;
    unsigned tail = 0;

    memset(orientation_distance, UINT8_MAX,
        sizeof orientation_distance);

    orientation_distance[0] = 0;
    queue[tail++] = 0;

    while (head < tail) {
        uint16_t here = queue[head++];

        for (uint8_t face = 0; face < 3; ++face) {
            uint16_t next = here;

            for (uint8_t turn = 0; turn < 3; ++turn) {
                next = orientation_next[face][next];

                if (next >= ORIENTATIONS) {
                    fputs("invalid orientation transition\n", stderr);
                    return 0;
                }

                if (orientation_distance[next] == UINT8_MAX) {
                    orientation_distance[next] =
                        (uint8_t)(orientation_distance[here] + 1);

                    queue[tail++] = next;
                }
            }
        }
    }

    if (tail != ORIENTATIONS) {
        fprintf(stderr, "incomplete orientation BFS: %u\n", tail);
        return 0;
    }

    uint8_t maximum = 0;

    for (unsigned i = 0; i < ORIENTATIONS; ++i) {
        if (orientation_distance[i] > maximum)
            maximum = orientation_distance[i];
    }

    fprintf(stderr,
        "orientation BFS: visited=%u maximum=%u solved=%u\n",
        tail, (unsigned)maximum,
        (unsigned)orientation_distance[0]);

    return 1;
}

static int valid(const state_t* state)
{
    uint8_t sum = 0;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        if (state->p[i] >= CUBIES || state->o[i] >= 3)
            return 0;
        for (uint8_t j = 0; j < i; ++j)
            if (state->p[j] == state->p[i])
                return 0;
        sum = (uint8_t)(sum + state->o[i]);
    }
    return sum % 3U == 0;
}

enum { MAX_DEPTH = 11 };

typedef struct {
    uint64_t expanded;
    uint64_t generated;
} search_stats_t;


static int is_solved(const state_t* state)
{
    for (uint8_t i = 0; i < CUBIES; ++i)
        if (state->p[i] != i || state->o[i] != 0)
            return 0;
    return 1;
}

static uint8_t heuristic(uint16_t p, uint16_t o)
{
    uint8_t hp = permutation_distance[p];
    uint8_t ho = orientation_distance[o];

    return hp > ho ? hp : ho;
}

static int search_with_limit(uint16_t start_p, uint16_t start_o, unsigned limit,
    uint8_t path[MAX_DEPTH], unsigned* length,
    search_stats_t* stats)/*輸入資料有
                            start_p 起始狀態的排列編號
                            start_o 起始狀態的朝向編號
                            limit	這次允許的步數上限
                            path	保存搜尋路徑上的操作編號
                            length	找到解法後，把步數寫到這裡
                            stats	記錄展開、產生的節點數*/
{
    uint16_t p_states[MAX_DEPTH + 1]; 
    uint16_t o_states[MAX_DEPTH + 1]; 
    uint8_t next_move[MAX_DEPTH + 1] = { 0 };
    uint16_t next_p_cache[MAX_DEPTH + 1];
    uint16_t next_o_cache[MAX_DEPTH + 1];
    unsigned depth = 0;
    *length = 0;
    if (limit > MAX_DEPTH)
        return 0;
    p_states[0] = start_p;
    o_states[0] = start_o;

    for (;;) {
        if (p_states[depth] == 0 && o_states[depth] == 0) {
            *length = depth;
            return 1;
        }

        if (depth == limit ||
            next_move[depth] == MOVES ||
            depth + heuristic(p_states[depth], o_states[depth]) > limit) {
            if (depth == 0)
                return 0;
            --depth;      
            continue;
        }

        if (next_move[depth] == 0)
            ++stats->expanded;
        uint8_t move = next_move[depth]++;

        if (depth > 0 && move / 3U == path[depth - 1] / 3U)
            continue;

        uint8_t face = (uint8_t)(move / 3U);

        
        if (move % 3U == 0) {
            next_p_cache[depth] = p_states[depth];
            next_o_cache[depth] = o_states[depth];
        }

        
        next_p_cache[depth] =
            permutation_next[face][next_p_cache[depth]];
        next_o_cache[depth] =
            orientation_next[face][next_o_cache[depth]];

        p_states[depth + 1] = next_p_cache[depth];
        o_states[depth + 1] = next_o_cache[depth];

        path[depth] = move;
        ++stats->generated;
        ++depth;
        next_move[depth] = 0; 
    }
}

static int solve_ida(const state_t* start, unsigned max_depth,
    uint8_t path[MAX_DEPTH], unsigned* length,
    search_stats_t* total, int verbose)
{
    uint32_t rank = rank_state(start);
    uint16_t start_p = (uint16_t)(rank / ORIENTATIONS);
    uint16_t start_o = (uint16_t)(rank % ORIENTATIONS);

    total->expanded = 0;
    total->generated = 0;
    if (max_depth > MAX_DEPTH)
        return 0;
    for (unsigned limit = heuristic(start_p, start_o);
        limit <= max_depth;
        ++limit) {
        search_stats_t current = { 0, 0 };
        int found = search_with_limit(start_p, start_o, limit, path, length, &current);
        total->expanded += current.expanded;
        total->generated += current.generated;
        if (verbose)
            fprintf(stderr, "limit=%u expanded=%llu generated=%llu %s\n",
                limit, (unsigned long long)current.expanded,
                (unsigned long long)current.generated,
                found ? "found" : "exhausted");
        if (found)
            return 1;
    }
    return 0;
}

static int parse_state(const char* input, state_t* state)
{
    for (int i = 0; i < 14; ++i) {
        int limit = i < 7 ? 7 : 3;
        if (input[i] < '1' || input[i] > '0' + limit)
            return 0;
        (i < 7 ? state->p : state->o)[i % 7] = (uint8_t)(input[i] - '1');
    }
    return input[14] == '\0' && valid(state);
}


static int output_failed(void)
{
    return fflush(stdout) != 0 || ferror(stdout);
}

static int self_test(void)
{
    const state_t solved = { { 0, 1, 2, 3, 4, 5, 6 },{ 0 } };
    state_t state;
    for (uint8_t move = 0; move < MOVES; ++move) {
        state = solved;
        state = apply_move(state, move);
        state = apply_move(state, inverse_move[move]);
        if (memcmp(&solved, &state, sizeof solved))
            return 0;
    }
    for (uint32_t rank = 0; rank < STATES; ++rank) {
        unrank_state(rank, &state);
        if (!valid(&state) || rank_state(&state) != rank)
            return 0;
    }
    return 1;
}

static int verify_searches(const uint8_t* distance, uint32_t count)
{
    clock_t begin = clock();

    for (uint32_t i = 0; i < count; ++i) {
        uint32_t rank =
            (uint32_t)(((uint64_t)i * STATES) / count);

        state_t start;
        unrank_state(rank, &start);

        uint8_t path[MAX_DEPTH];
        unsigned length = 0;
        search_stats_t stats;

        int found = solve_ida(
            &start, MAX_DEPTH, path, &length, &stats, 0);

        if (!found || length != distance[rank]) {
            fprintf(stderr,
                "H3 failed: rank=%u found=%d length=%u exact=%u\n",
                (unsigned)rank, found, length,
                (unsigned)distance[rank]);
            return 0;
        }

        state_t check = start;

        for (unsigned step = 0; step < length; ++step)
            check = apply_move(check, path[step]);

        if (!is_solved(&check)) {
            fprintf(stderr, "replay failed: rank=%u\n",
                (unsigned)rank);
            return 0;
        }

        if ((i + 1) % 10000 == 0)
            fprintf(stderr, "search verification: %u/%u\n",
                (unsigned)(i + 1), (unsigned)count);
    }

    fprintf(stderr,
        "search verification passed: %u states; seconds=%.3f\n",
        (unsigned)count,
        (double)(clock() - begin) / CLOCKS_PER_SEC);

    return 1;
}

static int verify_on_host(void)
{
    uint8_t* distance = malloc((size_t)STATES * sizeof * distance);
    uint32_t* queue = malloc((size_t)STATES * sizeof * queue);

    if (!distance || !queue) {
        free(distance);
        free(queue);
        fputs("could not allocate exact BFS tables\n", stderr);
        return 0;
    }

    memset(distance, UINT8_MAX, (size_t)STATES * sizeof * distance);

    unsigned head = 0;
    unsigned tail = 0;
    uint8_t maximum = 0;

    distance[0] = 0;
    queue[tail++] = 0;

    while (head < tail) {
        uint32_t here = queue[head++];

        uint16_t p = (uint16_t)(here / ORIENTATIONS);
        uint16_t o = (uint16_t)(here % ORIENTATIONS);

        for (uint8_t face = 0; face < 3; ++face) {
            uint16_t next_p = p;
            uint16_t next_o = o;

            for (uint8_t turn = 0; turn < 3; ++turn) {
                next_p = permutation_next[face][next_p];
                next_o = orientation_next[face][next_o];

                uint32_t next =
                    (uint32_t)next_p * ORIENTATIONS + next_o;

                if (distance[next] == UINT8_MAX) {
                    distance[next] =
                        (uint8_t)(distance[here] + 1);

                    queue[tail++] = next;

                    if (distance[next] > maximum)
                        maximum = distance[next];
                }
            }
        }
    }

    fprintf(stderr,
        "exact BFS: visited=%u maximum=%u solved=%u\n",
        tail, (unsigned)maximum, (unsigned)distance[0]);

    int passed = tail == STATES &&
        maximum == 11 &&
        distance[0] == 0;

    if (passed) {
        for (uint32_t rank = 0; rank < STATES; ++rank) {

            uint16_t p = (uint16_t)(rank / ORIENTATIONS);
            uint16_t o = (uint16_t)(rank % ORIENTATIONS);
            uint8_t h = heuristic(p, o);

            if (h > distance[rank]) {
                fprintf(stderr,
                    "H1 failed: rank=%u h=%u exact=%u\n",
                    (unsigned)rank,
                    (unsigned)h,
                    (unsigned)distance[rank]);

                passed = 0;
                break;
            }
        }

        if (passed)
            fputs("H1 passed: all 3674160 states\n", stderr);
    }

    free(queue);

    if (passed) 
        passed = verify_searches(distance, STATES);

    free(distance);

    return passed;
}

static int verify_distance_tables(void)
{
    const uint8_t* tables[2] = {
        permutation_distance,
        orientation_distance
    };

    const unsigned sizes[2] = {
        PERMUTATIONS, ORIENTATIONS
    };

    const unsigned expected_maximum[2] = { 7, 6 };

    const char* names[2] = {
        "permutation", "orientation"
    };

    for (unsigned table = 0; table < 2; ++table) {
        unsigned maximum = 0;

        if (tables[table][0] != 0) {
            fprintf(stderr, "%s solved entry is not zero\n",
                names[table]);
            return 0;
        }

        for (unsigned i = 0; i < sizes[table]; ++i) {
            unsigned value = tables[table][i];

            if (value == UINT8_MAX ||
                value > expected_maximum[table] ||
                (i != 0 && value == 0)) {
                fprintf(stderr,
                    "%s distance table failed: index=%u value=%u\n",
                    names[table], i, value);
                return 0;
            }

            if (value > maximum)
                maximum = value;
        }

        if (maximum != expected_maximum[table]) {
            fprintf(stderr, "%s maximum check failed\n",
                names[table]);
            return 0;
        }

        fprintf(stderr,
            "%s distance table passed: entries=%u maximum=%u solved=0\n",
            names[table], sizes[table], maximum);
    }

    return 1;
}

static int verify_transition_tables(void)
{
    const uint16_t* tables[2][3] = {
        {
            permutation_next[0],
            permutation_next[1],
            permutation_next[2]
        },
        {
            orientation_next[0],
            orientation_next[1],
            orientation_next[2]
        }
    };

    const unsigned sizes[2] = {
        PERMUTATIONS, ORIENTATIONS
    };

    const char* names[2] = {
        "permutation", "orientation"
    };

    state_t solved;
    unrank_state(0, &solved);

    for (unsigned table = 0; table < 2; ++table) {
        for (uint8_t face = 0; face < 3; ++face) {
            state_t moved = quarter_turn(solved, face);
            uint32_t rank = rank_state(&moved);

            unsigned expected_solved = table == 0
                ? rank / ORIENTATIONS
                : rank % ORIENTATIONS;

            if (tables[table][face][0] != expected_solved) {
                fprintf(stderr,
                    "%s transition solved entry failed: face=%u\n",
                    names[table], (unsigned)face);
                return 0;
            }

            unsigned maximum = 0;

            for (unsigned i = 0; i < sizes[table]; ++i) {
                unsigned current = i;

                for (unsigned turn = 0; turn < 4; ++turn) {
                    current = tables[table][face][current];

                    if (current >= sizes[table]) {
                        fprintf(stderr,
                            "%s transition out of range: face=%u index=%u\n",
                            names[table], (unsigned)face, i);
                        return 0;
                    }

                    if (current > maximum)
                        maximum = current;
                }

                if (current != i) {
                    fprintf(stderr,
                        "%s four-turn check failed: face=%u index=%u\n",
                        names[table], (unsigned)face, i);
                    return 0;
                }
            }

            if (maximum != sizes[table] - 1) {
                fputs("transition maximum check failed\n", stderr);
                return 0;
            }

            fprintf(stderr,
                "%s transitions passed: face=%u entries=%u maximum=%u solved_next=%u\n",
                names[table], (unsigned)face,
                sizes[table], maximum, expected_solved);
        }
    }

    return 1;
}

int main(int argc, char** argv)
{
    state_t state;

    build_transitions();
    if (!build_permutation_distances())
        return 1;
    if (!build_orientation_distances())
        return 1;
    if (!verify_distance_tables())
        return 1;

    if (!verify_transition_tables())
        return 1;

    if (!verify_on_host())
        return 1;

    if (argc == 2 && !strcmp(argv[1], "--self-test")) {
        if (!self_test()) {
            fputs("self-test failed\n", stderr);
            return 1;
        }
        puts("move/inverse and all 3674160 rank/unrank checks passed; no diameter proof");
        return output_failed();
    }
    if ((argc != 2 && argc != 3) || !parse_state(argv[1], &state)) {
        fprintf(stderr, "usage: %s PPPPPPPOOOOOOO [max-depth:0..11]\n",
            argc > 0 && argv[0] ? argv[0] : "solver");
        return 2;
    }

    uint32_t root_rank = rank_state(&state);
    uint16_t root_p = (uint16_t)(root_rank / ORIENTATIONS);
    uint16_t root_o = (uint16_t)(root_rank % ORIENTATIONS);

    fprintf(stderr, "root lower bound=%u\n",
        (unsigned)heuristic(root_p, root_o));

    unsigned max_depth = MAX_DEPTH;
    if (argc == 3) {
        if (argv[2][0] == '\0')
            return 2;
        max_depth = 0;
        for (const char* p = argv[2]; *p; ++p) {
            if (*p < '0' || *p > '9')
                return 2;
            max_depth = max_depth * 10U + (unsigned)(*p - '0');
            if (max_depth > MAX_DEPTH) {
                fputs("max-depth must be 0..11\n", stderr);
                return 2;
            }
        }
    }

    uint8_t path[MAX_DEPTH];
    unsigned length = 0;
    search_stats_t total;
    clock_t begin = clock();
    int found = solve_ida(&state, max_depth, path, &length, &total, 1);
    double cpu_seconds = (double)(clock() - begin) / CLOCKS_PER_SEC;
    fprintf(stderr, "total expanded=%llu generated=%llu cpu_seconds=%.6f\n",
        (unsigned long long)total.expanded,
        (unsigned long long)total.generated, cpu_seconds);
    if (!found) {
        fprintf(stderr, "No solution within %u moves (not a claim of unsolvability).\n",
            max_depth);
        return 3;
    }

    state_t check = state;
    for (unsigned i = 0; i < length; ++i)
        check = apply_move(check, path[i]);
    if (!is_solved(&check)) {
        fputs("internal error: returned path does not solve the cube\n", stderr);
        return 4;
    }
    for (unsigned i = 0; i < length; ++i)
        printf("%s%s", i ? " " : "", move_names[path[i]]);
    putchar('\n');
    fprintf(stderr, "solution_length=%u\n", length);
    return output_failed();
}