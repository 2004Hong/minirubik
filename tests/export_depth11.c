#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { CUBIES = 7, PERMUTATIONS = 5040, ORIENTATIONS = 729,
       STATES = PERMUTATIONS * ORIENTATIONS, EXPECTED_DEPTH11 = 2644 };
typedef struct { uint8_t p[7], o[7]; } state_t;
static uint16_t permutation_next[3][PERMUTATIONS];
static uint16_t orientation_next[3][ORIENTATIONS];
static const uint8_t source[3][7] = {
    {1,4,2,0,3,5,6}, {0,1,2,4,5,6,3}, {0,2,5,3,1,4,6}
};
static const uint8_t twist[3][7] = {
    {1,2,0,2,1,0,0}, {0,0,0,1,2,1,2}, {0,0,0,0,0,0,0}
};

static state_t quarter_turn(state_t state, unsigned face)
{
    state_t result;
    for (unsigned i = 0; i < 7; ++i) {
        unsigned from = source[face][i];
        result.p[i] = state.p[from];
        result.o[i] = (uint8_t)((state.o[from] + twist[face][i]) % 3U);
    }
    return result;
}

static uint32_t rank_state(const state_t* state)
{
    uint32_t p = 0, o = 0;
    for (unsigned i = 0; i < 7; ++i) {
        unsigned smaller = 0;
        for (unsigned j = i + 1; j < 7; ++j)
            if (state->p[j] < state->p[i]) ++smaller;
        p = p * (7U - i) + smaller;
    }
    for (unsigned i = 0; i < 6; ++i) o = o * 3U + state->o[i];
    return p * ORIENTATIONS + o;
}

static void unrank_state(uint32_t rank, state_t* state)
{
    uint8_t available[7] = {0,1,2,3,4,5,6};
    uint32_t p = rank / ORIENTATIONS, o = rank % ORIENTATIONS, f = 720;
    unsigned sum = 0;
    for (unsigned i = 0; i < 7; ++i) {
        unsigned q = p / f;
        p %= f;
        state->p[i] = available[q];
        for (unsigned j = q; j + 1 < 7 - i; ++j)
            available[j] = available[j + 1];
        if (i < 5) f /= 6U - i;
    }
    for (unsigned i = 6; i-- > 0;) {
        state->o[i] = (uint8_t)(o % 3U);
        sum += state->o[i];
        o /= 3U;
    }
    state->o[6] = (uint8_t)((3U - sum % 3U) % 3U);
}

static int valid_state(const state_t* state)
{
    unsigned seen = 0, sum = 0;
    for (unsigned i = 0; i < 7; ++i) {
        if (state->p[i] >= 7 || state->o[i] >= 3) return 0;
        unsigned bit = 1U << state->p[i];
        if (seen & bit) return 0;
        seen |= bit;
        sum += state->o[i];
    }
    return sum % 3U == 0;
}

static void build_transitions(void)
{
    state_t state;
    for (unsigned p = 0; p < PERMUTATIONS; ++p) {
        unrank_state(p * ORIENTATIONS, &state);
        for (unsigned face = 0; face < 3; ++face) {
            state_t next = quarter_turn(state, face);
            permutation_next[face][p] = (uint16_t)(rank_state(&next) / ORIENTATIONS);
        }
    }
    for (unsigned o = 0; o < ORIENTATIONS; ++o) {
        unrank_state(o, &state);
        for (unsigned face = 0; face < 3; ++face) {
            state_t next = quarter_turn(state, face);
            orientation_next[face][o] = (uint16_t)(rank_state(&next) % ORIENTATIONS);
        }
    }
}

int main(void)
{
    const char* output_name = "depth11_inputs.txt";
    uint8_t* distance = (uint8_t*)malloc((size_t)STATES);
    uint32_t* queue = (uint32_t*)malloc((size_t)STATES * sizeof *queue);
    if (!distance || !queue) {
        fputs("Could not allocate host BFS memory.\n", stderr);
        free(distance); free(queue);
        return 1;
    }
    build_transitions();
    memset(distance, 255, (size_t)STATES);
    uint32_t head = 0, tail = 1;
    unsigned maximum = 0, count = 0;
    queue[0] = 0;
    distance[0] = 0;
    while (head < tail) {
        uint32_t here = queue[head++];
        uint16_t p = (uint16_t)(here / ORIENTATIONS);
        uint16_t o = (uint16_t)(here % ORIENTATIONS);
        for (unsigned face = 0; face < 3; ++face) {
            uint16_t next_p = p, next_o = o;
            for (unsigned turn = 0; turn < 3; ++turn) {
                next_p = permutation_next[face][next_p];
                next_o = orientation_next[face][next_o];
                uint32_t next = (uint32_t)next_p * ORIENTATIONS + next_o;
                if (distance[next] == 255) {
                    distance[next] = (uint8_t)(distance[here] + 1);
                    queue[tail++] = next;
                    if (distance[next] > maximum) maximum = distance[next];
                }
            }
        }
    }
    free(queue);
    for (uint32_t rank = 0; rank < STATES; ++rank)
        if (distance[rank] == 11) ++count;
    printf("exact BFS: visited=%u maximum=%u solved=%u\n",
           (unsigned)tail, maximum, (unsigned)distance[0]);
    printf("depth-11 states: %u\n", count);
    if (tail != STATES || maximum != 11 || distance[0] != 0 || count != EXPECTED_DEPTH11) {
        fputs("BFS validation failed; no file exported.\n", stderr);
        free(distance);
        return 1;
    }
    /* Validate every record before creating the output file. */
    for (uint32_t rank = 0; rank < STATES; ++rank) {
        if (distance[rank] != 11) continue;
        state_t state;
        unrank_state(rank, &state);
        if (!valid_state(&state) || rank_state(&state) != rank) {
            fputs("Encoding validation failed.\n", stderr);
            free(distance);
            return 1;
        }
    }
    FILE* file = NULL;
#ifdef _MSC_VER
    if (fopen_s(&file, output_name, "w") != 0) file = NULL;
#else
    file = fopen(output_name, "w");
#endif
    if (!file) {
        fputs("Could not open depth11_inputs.txt in the working directory.\n", stderr);
        free(distance);
        return 1;
    }
    int write_failed = 0;
    for (uint32_t rank = 0; rank < STATES; ++rank) {
        if (distance[rank] != 11) continue;
        state_t state;
        char input[16];
        unrank_state(rank, &state);
        for (unsigned i = 0; i < 7; ++i) {
            input[i] = (char)('1' + state.p[i]);
            input[i + 7] = (char)('1' + state.o[i]);
        }
        input[14] = '\n'; input[15] = '\0';
        if (fputs(input, file) == EOF) { write_failed = 1; break; }
    }
    free(distance);
    if (ferror(file)) write_failed = 1;
    if (fclose(file) != 0) write_failed = 1;
    if (write_failed) {
        fputs("Export failed; discard the incomplete output file.\n", stderr);
        return 1;
    }
    printf("exported %u inputs to %s\n", count, output_name);
    return 0;
}
