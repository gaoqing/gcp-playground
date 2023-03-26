express = require('express');
const app = express();
const port = 6006;
app.get('/', (req, res) => {
    res.send(`Hello World! <br/><br/>You may want to access this: <a href="/index.html">Todo App</a>`)
});
app.use(express.static('static'));
app.listen(port, () => console.log('Example app listening on port 6006!'));
